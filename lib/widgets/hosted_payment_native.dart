import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
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
  late final WebViewController controller;
  @override
  void initState() {
    super.initState();
    final policy = PaymentNavigationPolicy(widget.returnUri);
    final params = WebViewPlatform.instance is WebKitWebViewPlatform
        ? WebKitWebViewControllerCreationParams(
            javaScriptCanOpenWindowsAutomatically: true)
        : const PlatformWebViewControllerCreationParams();
    controller = WebViewController.fromPlatformCreationParams(params,
        onPermissionRequest: (request) => request.deny())
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (value) {
          if (mounted) widget.onProgress(value);
        },
        onPageFinished: (url) {
          if (mounted && policy.isReturn(url)) widget.onReturn();
        },
        onNavigationRequest: (request) {
          if (policy.allowsNavigation(request.url)) {
            return NavigationDecision.navigate;
          }
          if (mounted) {
            widget.onError(
                'تعذر عرض هذه الخطوة داخل صفحة الدفع. تحقق من حالة العملية قبل المحاولة مجددًا.');
          }
          return NavigationDecision.prevent;
        },
        onWebResourceError: (error) {
          if (mounted && error.isForMainFrame == true) {
            widget.onError(
                'تعذر تحميل صفحة البنك. تحقق من اتصال الإنترنت ثم أعد فتح الدفع.');
          }
        },
        onHttpError: (error) async {
          final currentUrl = await controller.currentUrl();
          if (mounted &&
              error.request?.uri == Uri.tryParse(currentUrl ?? '') &&
              (error.response?.statusCode ?? 0) >= 400) {
            widget.onError(
                'صفحة البنك غير متاحة الآن. يمكنك التحقق من حالة الدفع أو إعادة فتحها.');
          }
        },
      ));
    _loadCheckout();
  }

  Future<void> _loadCheckout() async {
    try {
      final cookieManager = WebViewCookieManager().platform;
      final platformController = controller.platform;
      // Some issuer 3DS challenges are embedded in the hosted bank page.
      // This setting is scoped to this payment WebView, not a device browser.
      if (cookieManager is AndroidWebViewCookieManager &&
          platformController is AndroidWebViewController) {
        await cookieManager.setAcceptThirdPartyCookies(
            platformController, true);
      }
      if (mounted) await controller.loadRequest(Uri.parse(widget.checkoutUrl));
    } catch (_) {
      if (mounted) {
        widget.onError(
            'تعذر تجهيز صفحة البنك داخل التطبيق. أعد فتح الدفع للمحاولة مجددًا.');
      }
    }
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: controller);
}

bool get canContinuePaymentInSameTab => false;
void continuePaymentInSameTab(String url) => throw UnsupportedError('Web only');
