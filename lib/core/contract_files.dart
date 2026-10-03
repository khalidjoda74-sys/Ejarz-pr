import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'firebase_bootstrap.dart';
import 'legal_links.dart';

class ContractFiles {
  static const maxBytes = 10 * 1024 * 1024;
  static const demoPdf = '${LegalLinks.baseUrl}/demo/ejarz-demo-contract.pdf';

  static String contentType(String name, Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const FormatException(
          'اختر ملفًا غير فارغ بحجم لا يتجاوز 10 ميجابايت.');
    }
    final extension = name.split('.').last.toLowerCase();
    bool starts(List<int> signature) =>
        bytes.length >= signature.length &&
        List.generate(signature.length, (i) => bytes[i] == signature[i])
            .every((v) => v);
    if (extension == 'pdf' && starts([0x25, 0x50, 0x44, 0x46, 0x2d])) {
      return 'application/pdf';
    }
    if (extension == 'png' && starts([137, 80, 78, 71, 13, 10, 26, 10])) {
      return 'image/png';
    }
    if ((extension == 'jpg' || extension == 'jpeg') &&
        starts([255, 216, 255])) {
      return 'image/jpeg';
    }
    throw const FormatException(
        'الملف غير مدعوم أو لا يطابق نوعه. اختر PDF أو صورة JPG أو PNG.');
  }

  static Future<String> upload(String name, Uint8List bytes) async {
    final type = contentType(name, bytes);
    await FirebaseBootstrap.ready;
    if (!FirebaseBootstrap.initialized ||
        FirebaseAuth.instance.currentUser == null) {
      throw StateError('اتصل بالإنترنت وسجّل الدخول لحفظ المرفق.');
    }
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final extension = name.split('.').last.toLowerCase();
    final ref = FirebaseStorage.instance.ref(
        'users/$uid/attachments/${DateTime.now().microsecondsSinceEpoch}.$extension');
    final task = ref.putData(bytes, SettableMetadata(contentType: type));
    try {
      await task.timeout(const Duration(seconds: 90));
      return await ref.getDownloadURL();
    } catch (_) {
      await task.cancel();
      rethrow;
    }
  }
}
