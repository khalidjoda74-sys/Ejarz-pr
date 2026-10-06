import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

String _text(Object? value, [String fallback = 'غير متاح']) {
  final text = '${value ?? ''}'.trim();
  return text.isEmpty ? fallback : text;
}

String receiptRequestNumber(Map<String, dynamic> invoice,
        {Map<String, dynamic>? contract}) =>
    _text(invoice['requestNumber'],
        _text(contract?['requestNumber'], _text(contract?['orderNumber'])));

Map<String, dynamic> receiptDetails(Map<String, dynamic> invoice,
        {Map<String, dynamic>? contract, Map<String, dynamic>? payment}) =>
    {
      ...invoice,
      'requestNumber': receiptRequestNumber(invoice, contract: contract),
      'providerReference': _text(
          invoice['providerReference'],
          _text(payment?['providerReference'],
              _text(contract?['paymentProviderReference']))),
      'customerName':
          _text(invoice['customerName'], _text(contract?['customerName'])),
      'paidAt': invoice['paidAt'] ?? payment?['paidAt'] ?? contract?['paidAt'],
    };

String _date(Object? value) {
  DateTime? date;
  if (value is Timestamp) date = value.toDate();
  if (value is DateTime) date = value;
  if (value is String) date = DateTime.tryParse(value);
  if (date == null) return 'غير متاح';
  final local = date.toUtc().add(const Duration(hours: 3));
  String two(int v) => v.toString().padLeft(2, '0');
  return '${local.year}/${two(local.month)}/${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

Future<Uint8List> receiptPdf(Map<String, dynamic> invoice) async {
  final amount = invoice['amount'];
  if (amount is! num || !amount.isFinite || amount < 0) {
    throw StateError('قيمة رسوم المستند غير صحيحة');
  }
  final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/IBMPlexSansArabic-Regular.ttf'));
  final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/IBMPlexSansArabic-Bold.ttf'));
  final logo = pw.MemoryImage(
      (await rootBundle.load('assets/images/aqdak_mark.png'))
          .buffer
          .asUint8List());
  final green = PdfColor.fromHex('#193E2F');
  final document = pw.Document(
      title: 'مستند رسوم الخدمة',
      author: 'عقدك',
      theme: pw.ThemeData.withFont(base: regular, bold: bold));
  const statuses = {
    'paid': 'مدفوع',
    'pending': 'بانتظار الدفع',
    'refunded': 'مسترد',
    'partiallyRefunded': 'مسترد جزئيًا',
    'cancelled': 'ملغي',
    'void': 'ملغي'
  };
  pw.Widget row(String label, String value, {bool ltr = false}) => pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 11, horizontal: 12),
      decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300))),
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.SizedBox(
            width: 135,
            child: pw.Text(label,
                style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold, color: green))),
        pw.SizedBox(width: 12),
        pw.Expanded(
            child: pw.Text(value,
                textDirection:
                    ltr ? pw.TextDirection.ltr : pw.TextDirection.rtl,
                textAlign: pw.TextAlign.right)),
      ]));
  document.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      textDirection: pw.TextDirection.rtl,
      header: (_) => pw.Column(children: [
            pw.Row(children: [
              pw.Image(logo, width: 48, height: 48),
              pw.SizedBox(width: 12),
              pw.Text('عقدك',
                  style: pw.TextStyle(
                      fontSize: 26,
                      color: green,
                      fontWeight: pw.FontWeight.bold))
            ]),
            pw.SizedBox(height: 16),
            pw.Divider(color: green),
          ]),
      footer: (context) => pw.Column(children: [
            pw.Divider(color: PdfColors.grey300),
            pw.Text(
                'التوقيت: الرياض • صفحة ${context.pageNumber} من ${context.pagesCount}',
                style:
                    const pw.TextStyle(fontSize: 9, color: PdfColors.grey600))
          ]),
      build: (_) => [
            pw.SizedBox(height: 22),
            pw.Text(
                invoice['isDemo'] == true
                    ? 'مستند تجريبي'
                    : 'مستند رسوم الخدمة',
                style: pw.TextStyle(
                    fontSize: 22,
                    color: green,
                    fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 18),
            row('رقم المستند', _text(invoice['invoiceNumber']), ltr: true),
            row('رقم الطلب', _text(invoice['requestNumber']), ltr: true),
            row('مرجع عملية الدفع', _text(invoice['providerReference']),
                ltr: true),
            row('اسم العميل', _text(invoice['customerName'])),
            row('تاريخ المستند', _date(invoice['createdAt']), ltr: true),
            if (invoice['paidAt'] != null)
              row('تاريخ السداد', _date(invoice['paidAt']), ltr: true),
            row('الحالة', statuses[invoice['status']] ?? 'غير متاح'),
            row('رسوم خدمة التطبيق', '${amount.toStringAsFixed(2)} ريال سعودي'),
            pw.SizedBox(height: 24),
            pw.Text(
                invoice['isDemo'] == true
                    ? 'بيانات تجريبية لا تثبت تحصيلًا ماليًا.'
                    : 'مستند داخلي لرسوم الخدمة. الفوترة الضريبية الخارجية ليست مفعلة.',
                style:
                    const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
          ]));
  return document.save();
}

Future<void> downloadReceipt(Map<String, dynamic> invoice,
    {bool Function()? isCurrentAccount}) async {
  final bytes = await receiptPdf(invoice);
  if (isCurrentAccount != null && !isCurrentAccount()) return;
  final number = _text(invoice['invoiceNumber'], 'service-fees')
      .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '-');
  final path = await FilePicker.platform.saveFile(
      dialogTitle: 'تنزيل إيصال PDF',
      fileName: 'aqdak-receipt-$number.pdf',
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      bytes: bytes);
  if (!kIsWeb &&
      path != null &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS)) {
    if (isCurrentAccount != null && !isCurrentAccount()) return;
    await XFile.fromData(bytes, mimeType: 'application/pdf').saveTo(path);
  }
}
