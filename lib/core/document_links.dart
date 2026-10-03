import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/common.dart';

Uri? safeDocumentUri(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri;
}

Future<void> openDocument(BuildContext context, String value) async {
  final uri = safeDocumentUri(value);
  if (uri == null) {
    showAppSnackBar(
        context, 'لا يوجد رابط تنزيل صالح لهذا الملف. تواصل مع الدعم.');
    return;
  }
  try {
    final opened = await launchUrl(uri,
        mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
    if (!opened && context.mounted) {
      showAppSnackBar(
          context, 'تعذر فتح الملف. اسمح بفتح نافذة جديدة ثم أعد المحاولة.');
    }
  } catch (_) {
    if (context.mounted) {
      showAppSnackBar(context, 'تعذر فتح الملف الآن. حاول مرة أخرى.');
    }
  }
}
