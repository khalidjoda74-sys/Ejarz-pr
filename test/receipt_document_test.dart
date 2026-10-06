import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:aqdak/core/app_controller.dart';
import 'package:aqdak/screens/account_records.dart';
import 'package:aqdak/core/receipt_document.dart';
import 'package:aqdak/core/receipt_share.dart';
import 'package:aqdak/widgets/receipt_actions_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'contract_form_audit_test.dart' show shell;

class ReceiptFilePicker extends FilePicker {
  Uint8List? savedBytes;
  String? savedName;
  List<String>? extensions;
  String? destination;
  int calls = 0;
  @override
  Future<String?> saveFile(
      {String? dialogTitle,
      String? fileName,
      String? initialDirectory,
      FileType type = FileType.any,
      List<String>? allowedExtensions,
      Uint8List? bytes,
      bool lockParentWindow = false}) async {
    calls++;
    savedBytes = bytes;
    savedName = fileName;
    extensions = allowedExtensions;
    return destination;
  }
}

class FakeReceiptShare implements ReceiptShare {
  @override
  bool supported = true;
  int calls = 0;
  Completer<void>? pending;
  bool fail = false;
  @override
  Future<void> share(Rect origin) async {
    expect(origin.width, greaterThan(0));
    calls++;
    if (fail) throw StateError('share failed');
    await pending?.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'PDF download uses PDF bytes and extension, handles desktop and account changes',
      () async {
    final picker = ReceiptFilePicker();
    FilePicker? original;
    try {
      original = FilePicker.platform;
    } catch (_) {}
    FilePicker.platform = picker;
    addTearDown(() {
      if (original != null) FilePicker.platform = original;
      debugDefaultTargetPlatformOverride = null;
    });
    final invoice = <String, dynamic>{
      'invoiceNumber': 'INV-2026-10-18',
      'requestNumber': 'AQ-2026-10-45',
      'amount': 299,
      'status': 'paid'
    };
    await downloadReceipt(invoice, isCurrentAccount: () => false);
    expect(picker.calls, 0);
    await downloadReceipt(invoice);
    expect(picker.savedName, 'aqdak-receipt-INV-2026-10-18.pdf');
    expect(picker.extensions, ['pdf']);
    expect(ascii.decode(picker.savedBytes!.take(5).toList()), '%PDF-');
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final file = File('tmp/pdfs/desktop-receipt-test.pdf').absolute;
    file.parent.createSync(recursive: true);
    picker.destination = file.path;
    await downloadReceipt(invoice);
    expect(picker.savedBytes, isNull);
    expect(ascii.decode(file.readAsBytesSync().take(5).toList()), '%PDF-');
    file.deleteSync();
  });
  testWidgets('invoice card shows public numbers in LTR and PDF download',
      (tester) async {
    final picker = ReceiptFilePicker();
    final originalPicker = FilePicker.platform;
    FilePicker.platform = picker;
    addTearDown(() => FilePicker.platform = originalPicker);
    final controller = AppController();
    addTearDown(controller.dispose);
    controller.invoices.add({
      'id': 'internal-invoice',
      'contractId': 'internal-contract',
      'paymentId': 'internal-payment',
      'invoiceNumber': 'INV-2026-10-18',
      'requestNumber': 'AQ-2026-10-45',
      'providerReference': 'BANK-123456',
      'customerName': 'خالد أحمد',
      'amount': 299,
      'status': 'paid'
    });
    await tester.pumpWidget(AppScope(
        controller: controller, child: shell(const CustomerInvoicesScreen())));
    await tester.pumpAndSettle();
    expect(find.text('ملف PDF'), findsOneWidget);
    expect(find.textContaining('HTML'), findsNothing);
    expect(find.textContaining('internal-'), findsNothing);
    expect(tester.widget<Text>(find.text('AQ-2026-10-45')).textDirection,
        TextDirection.ltr);
    expect(find.text('BANK-123456'), findsOneWidget);
    await tester.tap(find.text('ملف PDF'));
    await tester.pumpAndSettle();
    expect(find.byType(ReceiptActionsDialog), findsOneWidget);
    expect(find.text('مشاركة'), findsOneWidget);
    expect(find.text('تحميل'), findsOneWidget);
    expect(picker.calls, 0);
    await tester.tap(find.text('إغلاق'));
    await tester.pumpAndSettle();
    expect(picker.calls, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'PDF options require a choice, prevent repeated sharing and allow download after failure',
      (tester) async {
    final picker = ReceiptFilePicker();
    final original = FilePicker.platform;
    FilePicker.platform = picker;
    addTearDown(() => FilePicker.platform = original);
    final share = FakeReceiptShare();
    final bytes = Uint8List.fromList(ascii.encode('%PDF-test'));
    await tester.pumpWidget(shell(Builder(
        builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => ReceiptActionsDialog(
                      bytes: bytes,
                      fileName: 'receipt.pdf',
                      share: share,
                      isCurrentAccount: () => true)),
              child: const Text('open'),
            ))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(picker.calls, 0);
    expect(share.calls, 0);
    expect(find.text('مشاركة'), findsOneWidget);
    expect(find.text('تحميل'), findsOneWidget);
    share.pending = Completer<void>();
    await tester.tap(find.text('مشاركة'));
    await tester.pump();
    await tester.tap(find.text('مشاركة'));
    expect(share.calls, 1);
    share.pending!.complete();
    await tester.pumpAndSettle();
    share.fail = true;
    await tester.tap(find.text('مشاركة'));
    await tester.pumpAndSettle();
    expect(find.textContaining('تعذرت مشاركة'), findsOneWidget);
    expect(picker.calls, 0);
    await tester.tap(find.text('تحميل'));
    await tester.pumpAndSettle();
    expect(picker.savedBytes, bytes);
    expect(picker.savedName, 'receipt.pdf');
    expect(find.byType(ReceiptActionsDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('unsupported sharing and account change never export files',
      (tester) async {
    final share = FakeReceiptShare()..supported = false;
    var current = true;
    await tester.pumpWidget(shell(Builder(
        builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => ReceiptActionsDialog(
                      bytes: Uint8List(0),
                      fileName: 'receipt.pdf',
                      share: share,
                      isCurrentAccount: () => current)),
              child: const Text('open'),
            ))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('مشاركة الملفات غير مدعومة'), findsOneWidget);
    await tester.tap(find.text('مشاركة'));
    expect(share.calls, 0);
    current = false;
    await tester.tap(find.text('تحميل'));
    await tester.pumpAndSettle();
    expect(find.byType(ReceiptActionsDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
  test('receipt uses public references and preserves legacy request numbers',
      () {
    final invoice = {
      'contractId': 'internal-contract',
      'paymentId': 'internal-payment'
    };
    final details = receiptDetails(invoice, contract: {
      'requestNumber': 'REQ-2025-ABC123',
      'customerName': 'خالد أحمد',
    }, payment: {
      'providerReference': 'BANK-123456789',
      'paidAt': DateTime.utc(2026, 10, 6)
    });
    expect(details['requestNumber'], 'REQ-2025-ABC123');
    expect(details['providerReference'], 'BANK-123456789');
    expect(receiptRequestNumber(invoice), 'غير متاح');
    expect(receiptRequestNumber(invoice, contract: {'orderNumber': 'OLD-45'}),
        'OLD-45');
    expect(receiptDetails(invoice)['providerReference'], 'غير متاح');
    expect(
        receiptDetails({...invoice, 'requestNumber': 'AQ-2026-10-45'},
            contract: {'requestNumber': 'REQ-OLD'})['requestNumber'],
        'AQ-2026-10-45');
  });
  test('PDF validates amount and renders paid and long Arabic receipts',
      () async {
    final base = <String, dynamic>{
      'invoiceNumber': 'INV-2026-10-18',
      'requestNumber': 'AQ-2026-10-45',
      'providerReference': 'BANK-739201846521',
      'customerName': 'خالد أحمد محمد',
      'amount': 299.0,
      'status': 'paid',
      'createdAt': DateTime.utc(2026, 10, 6, 7, 30),
      'paidAt': DateTime.utc(2026, 10, 6, 7, 32),
    };
    for (final entry in {
      'receipt-paid.pdf': base,
      'receipt-long-arabic.pdf': {
        ...base,
        'status': 'partiallyRefunded',
        'customerName':
            'اسم عميل عربي طويل لاختبار التفاف النص والحفاظ على قراءة بيانات المستند كاملة ' *
                4
      },
    }.entries) {
      final bytes = await receiptPdf(entry.value);
      expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
      expect(bytes.length, greaterThan(10000));
      final file = File('output/pdf/receipts/${entry.key}');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes);
    }
    for (final amount in [-1, double.nan, double.infinity, null]) {
      await expectLater(
          receiptPdf({...base, 'amount': amount}), throwsStateError);
    }
  });
}
