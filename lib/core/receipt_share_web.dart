import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui';
import 'package:web/web.dart' as web;
import 'receipt_share.dart';

ReceiptShare prepareReceiptShare(Uint8List bytes, String name) =>
    _WebReceiptShare(bytes, name);

class _WebReceiptShare implements ReceiptShare {
  final web.ShareData data;
  _WebReceiptShare(Uint8List bytes, String name)
      : data = web.ShareData(
            files: [
          web.File([bytes.toJS].toJS, name,
              web.FilePropertyBag(type: 'application/pdf'))
        ].toJS);

  @override
  bool get supported {
    try {
      return web.window.isSecureContext && web.window.navigator.canShare(data);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> share(Rect origin) async {
    // File is prepared before the click to preserve browser user activation.
    try {
      await web.window.navigator.share(data).toDart;
    } catch (error) {
      final jsError = error as JSObject;
      if (jsError.isA<web.DOMException>() &&
          (jsError as web.DOMException).name == 'AbortError') {
        return;
      }
      rethrow;
    }
  }
}
