@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'dart:ui';
import 'package:web/web.dart' as web;
import 'package:flutter_test/flutter_test.dart';
import 'package:aqdak/core/receipt_share_web.dart';

void main() {
  test('web shares a named PDF file, handles cancellation and reports errors',
      () async {
    final navigator = web.window.navigator;
    final oldCanShare = navigator.getProperty<JSAny?>('canShare'.toJS);
    final oldShare = navigator.getProperty<JSAny?>('share'.toJS);
    addTearDown(() {
      navigator.setProperty('canShare'.toJS, oldCanShare);
      navigator.setProperty('share'.toJS, oldShare);
    });
    var allowed = true;
    navigator.setProperty(
        'canShare'.toJS, ((web.ShareData data) => allowed).toJS);
    web.ShareData? shared;
    var outcome = '';
    navigator.setProperty(
        'share'.toJS,
        ((web.ShareData data) {
          shared = data;
          if (outcome.isEmpty) return Future<JSAny?>.value(null).toJS;
          return globalContext
              .getProperty<JSObject>('Promise'.toJS)
              .callMethod<JSPromise<JSAny?>>(
                  'reject'.toJS, web.DOMException('test', outcome));
        }).toJS);
    final bytes = Uint8List.fromList(ascii.encode('%PDF-test'));
    final share =
        prepareReceiptShare(bytes, 'aqdak-receipt-INV-2026-10-18.pdf');
    expect(share.supported, isTrue);
    expect(shared, isNull);
    await share.share(const Rect.fromLTWH(1, 1, 100, 40));
    final file = shared!.files.toDart.single;
    expect(file.name, 'aqdak-receipt-INV-2026-10-18.pdf');
    expect(file.type, 'application/pdf');
    expect((await file.arrayBuffer().toDart).toDart.asUint8List(), bytes);
    outcome = 'AbortError';
    await share.share(Rect.zero);
    outcome = 'NotAllowedError';
    await expectLater(share.share(Rect.zero), throwsA(anything));
    allowed = false;
    expect(share.supported, isFalse);
    navigator.setProperty('canShare'.toJS, null);
    expect(share.supported, isFalse);
  });
}
