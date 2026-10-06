// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import '../core/payment_navigation.dart';

class HostedPaymentView extends StatefulWidget {
  final String checkoutUrl, paymentId;
  final Uri returnUri;
  final VoidCallback onReturn;
  final ValueChanged<int> onProgress;
  final ValueChanged<String> onError;
  const HostedPaymentView(
      {super.key,
      required this.checkoutUrl,
      required this.paymentId,
      required this.returnUri,
      required this.onReturn,
      required this.onProgress,
      required this.onError});
  @override
  State<HostedPaymentView> createState() => _HostedPaymentViewState();
}

class _HostedPaymentViewState extends State<HostedPaymentView> {
  StreamSubscription<html.MessageEvent>? messages;
  StreamSubscription<html.Event>? loaded, errors;
  html.MutationObserver? attachment;
  @override
  void dispose() {
    messages?.cancel();
    loaded?.cancel();
    errors?.cancel();
    attachment?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView.fromTagName(
        tagName: 'iframe',
        onElementCreated: (element) {
          final frame = element as html.IFrameElement;
          frame.title = 'الدفع الآمن عبر بوابة البنك';
          frame.style
            ..border = '0'
            ..width = '100%'
            ..height = '100%'
            ..backgroundColor = 'white';
          frame.setAttribute('allow', 'payment');
          // Keep redirects inside this frame. A bank that requires a top-level
          // context can be opened by the customer in the SAME tab below.
          frame.setAttribute(
              'sandbox', 'allow-forms allow-scripts allow-same-origin');
          var navigationStarted = false;
          loaded = frame.onLoad.listen((_) {
            if (mounted && navigationStarted) widget.onProgress(100);
          });
          errors = frame.onError.listen((_) {
            if (mounted) {
              widget.onError(
                  'تعذر عرض صفحة البنك. يمكنك استكمال الدفع في نفس التبويب.');
            }
          });
          messages = html.window.onMessage.listen((event) {
            if (!mounted ||
                event.source != frame.contentWindow ||
                event.origin != widget.returnUri.origin) {
              return;
            }
            final data = event.data;
            if (data is Map &&
                data['type'] == 'aqdak-payment-return' &&
                (data['paymentId'] == widget.paymentId ||
                    data['paymentId'] == '')) {
              widget.onReturn();
            }
          });
          // Flutter creates platform elements before attaching them. Start the
          // bank navigation only once the iframe has a browsing context.
          void startNavigation() {
            if (!mounted || navigationStarted || frame.isConnected != true) {
              return;
            }
            navigationStarted = true;
            attachment?.disconnect();
            frame.src = widget.checkoutUrl;
          }

          attachment = html.MutationObserver((_, __) => startNavigation())
            ..observe(html.document.documentElement!,
                childList: true, subtree: true);
          startNavigation();
        },
      );
}

bool get canContinuePaymentInSameTab => true;
void continuePaymentInSameTab(String url) {
  if (!PaymentNavigationPolicy.validCheckout(url)) {
    throw ArgumentError('Invalid checkout URL');
  }
  html.window.location.assign(url);
}
