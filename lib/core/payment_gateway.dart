import 'package:cloud_functions/cloud_functions.dart';
import 'firebase_repository.dart';
import 'models.dart';

abstract class ContractPaymentGateway {
  Future<Map<String, dynamic>> restore(String contractId);
  Future<Map<String, dynamic>> create(String contractId);
  Future<String> check(String paymentId);
  Future<ContractRecord?> contract(String contractId);
  Future<void> transfer(String contractId, String reference);
}

class FirebaseContractPaymentGateway implements ContractPaymentGateway {
  Future<Map<String, dynamic>> _call(
      String name, Map<String, dynamic> data) async {
    final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable(name)
        .call(data);
    return Map<String, dynamic>.from(result.data as Map);
  }

  @override
  Future<Map<String, dynamic>> restore(String contractId) =>
      _call('getContractPaymentAttempt', {'contractId': contractId});
  @override
  Future<Map<String, dynamic>> create(String contractId) => _call(
      'createPaymentAttempt', {'contractId': contractId, 'method': 'neoleap'});
  @override
  Future<String> check(String paymentId) async =>
      (await _call('checkNeoleapPayment', {'paymentId': paymentId}))['status']
          as String;
  @override
  Future<ContractRecord?> contract(String contractId) =>
      FirebaseRepository().fetchContract(contractId);
  @override
  Future<void> transfer(String contractId, String reference) async {
    await _call('createPaymentAttempt', {
      'contractId': contractId,
      'method': 'bankTransfer',
      'reference': reference
    });
  }
}
