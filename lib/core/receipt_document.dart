import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'brand_asset.dart';

String receiptHtml(Map<String, dynamic> invoice) {
  String esc(Object? value) => const HtmlEscape().convert('${value ?? ''}');
  final amount = (invoice['amount'] as num?)?.toStringAsFixed(2) ?? '0.00';
  return '''<!doctype html><html lang="ar" dir="rtl"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>إيصال عقدك</title><style>body{font:16px/1.9 Tahoma,Arial,sans-serif;color:#193e2f;max-width:720px;margin:40px auto;padding:24px}h1{display:flex;align-items:center;gap:12px;border-bottom:2px solid #196345;padding-bottom:16px}h1 img{width:52px;height:52px;object-fit:contain}table{width:100%;border-collapse:collapse}td{padding:12px;border-bottom:1px solid #ddd}small{color:#666}</style><h1><img src="$aqdakMarkDataUri" alt="">عقدك</h1><h2>${invoice['isDemo'] == true ? 'مستند تجريبي' : 'مستند رسوم الخدمة'}</h2><p>رقم المستند: ${esc(invoice['invoiceNumber'] ?? invoice['id'])}</p><table><tr><td>الطلب</td><td>${esc(invoice['contractId'])}</td></tr><tr><td>العملية</td><td>${esc(invoice['paymentId'])}</td></tr><tr><td>رسوم خدمة التطبيق</td><td>${esc(amount)} ريال سعودي</td></tr><tr><td>الحالة</td><td>${invoice['status'] == 'paid' ? 'مدفوع' : 'معلق'}</td></tr></table><p><small>${invoice['isDemo'] == true ? 'بيانات تجريبية لا تثبت تحصيلًا ماليًا.' : 'مستند داخلي لرسوم الخدمة. الفوترة الضريبية الخارجية ليست مفعلة.'}</small></p></html>''';
}

Future<void> downloadReceipt(Map<String, dynamic> invoice) async {
  await FilePicker.platform.saveFile(
      dialogTitle: 'تنزيل الإيصال القابل للطباعة',
      fileName: 'aqdak-receipt-${invoice['id']}.html',
      type: FileType.custom,
      allowedExtensions: ['html'],
      bytes: Uint8List.fromList(utf8.encode(receiptHtml(invoice))));
}
