import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:aqdak/core/app_controller.dart';
import 'package:aqdak/screens/account_records.dart';
import 'package:aqdak/core/receipt_document.dart';
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
    expect(file.readAsBytesSync(), picker.savedBytes);
    file.deleteSync();
  });
  testWidgets('invoice card shows public numbers in LTR and PDF download',
      (tester) async {
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
    expect(find.text('تنزيل إيصال PDF'), findsOneWidget);
    expect(find.textContaining('HTML'), findsNothing);
    expect(find.textContaining('internal-'), findsNothing);
    expect(tester.widget<Text>(find.text('AQ-2026-10-45')).textDirection,
        TextDirection.ltr);
    expect(find.text('BANK-123456'), findsOneWidget);
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
