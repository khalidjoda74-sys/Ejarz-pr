import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import 'receipt_share.dart';

ReceiptShare prepareReceiptShare(Uint8List bytes, String name) =>
    _NativeReceiptShare(bytes, name);

class _NativeReceiptShare implements ReceiptShare {
  final Uint8List bytes;
  final String name;
  _NativeReceiptShare(this.bytes, this.name);

  @override
  bool get supported => defaultTargetPlatform != TargetPlatform.linux;

  @override
  Future<void> share(Rect origin) async {
    await Share.shareXFiles(
      [XFile.fromData(bytes, mimeType: 'application/pdf')],
      fileNameOverrides: [name],
      sharePositionOrigin: origin,
    );
  }
}
