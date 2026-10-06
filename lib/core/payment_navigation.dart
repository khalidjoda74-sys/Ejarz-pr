/// Only the server callback may trigger verification. A URL or browser message
/// never proves that money was collected.
class PaymentNavigationPolicy {
  final Uri returnUri;
  const PaymentNavigationPolicy(this.returnUri);

  static bool validCheckout(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443)) {
      return false;
    }
    return ['neoleap.com.sa', 'alrajhibank.com.sa']
        .any((host) => uri.host == host || uri.host.endsWith('.$host'));
  }

  bool isReturn(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.origin == returnUri.origin &&
        uri.path == returnUri.path &&
        uri.userInfo.isEmpty;
  }

  // Issuer authentication may redirect to another bank's HTTPS domain.
  // Never launch custom schemes, HTTP, downloads or external applications.
  bool allowsNavigation(String value) {
    final uri = Uri.tryParse(value);
    return value == 'about:blank' ||
        (uri != null &&
            uri.scheme == 'https' &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty);
  }
}
