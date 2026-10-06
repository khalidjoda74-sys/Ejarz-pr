// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

void rememberPaymentContract(String contractId) {
  try {
    html.window.sessionStorage['aqdak-checkout-contract'] = contractId;
  } catch (_) {/* A verified callback may still supply the contract ID. */}
}

String? consumePaymentContract() {
  try {
    final value = html.window.sessionStorage['aqdak-checkout-contract'];
    html.window.sessionStorage.remove('aqdak-checkout-contract');
    return value;
  } catch (_) {
    return null;
  }
}
