import 'dart:typed_data';
import 'dart:ui';

abstract class ReceiptShare {
  bool get supported;
  Future<void> share(Rect origin);
}

typedef ReceiptShareFactory = ReceiptShare Function(
    Uint8List bytes, String name);
