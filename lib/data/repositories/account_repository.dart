import 'package:cloud_functions/cloud_functions.dart';

class AccountRepository {
  AccountRepository._();

  static final AccountRepository instance = AccountRepository._();

  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  Future<void> deleteMyAccount() async {
    final callable = _functions.httpsCallable('deleteMyAccount');
    await callable.call<Object?>();
  }
}
