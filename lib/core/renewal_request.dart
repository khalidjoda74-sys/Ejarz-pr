import 'dart:math';
import 'contract_calculation_engine.dart';
import 'contract_validators.dart';

class RenewalRequest {
  final String submissionId;
  String idNumber;
  String birthDate;
  String mobile;
  String fileName;
  String fileUrl;
  String sourceContractId;

  RenewalRequest(
      {String? submissionId,
      this.idNumber = '',
      this.birthDate = '',
      this.mobile = '',
      this.fileName = '',
      this.fileUrl = '',
      this.sourceContractId = ''})
      : submissionId = submissionId ??
            'renewal_${DateTime.now().microsecondsSinceEpoch}_${List.generate(12, (_) => Random.secure().nextInt(16).toRadixString(16)).join()}';

  static String normalize(String value) =>
      ContractCalculationEngine.normalizeDigits(value.trim());
  static String? validateIdentity(String? value) =>
      RegExp(r'^[12]\d{9}$').hasMatch(normalize(value ?? ''))
          ? null
          : 'أدخل هوية أو إقامة من 10 أرقام تبدأ بـ 1 أو 2';
  static String? validateMobile(String? value) =>
      RegExp(r'^05\d{8}$').hasMatch(normalize(value ?? ''))
          ? null
          : 'أدخل رقم جوال من 10 أرقام يبدأ بـ 05';

  void validate() {
    for (final error in [
      validateIdentity(idNumber),
      validateAdultBirthDate(normalize(birthDate)),
      validateMobile(mobile)
    ]) {
      if (error != null) throw FormatException(error);
    }
    if (fileUrl.isEmpty || !fileName.toLowerCase().endsWith('.pdf')) {
      throw const FormatException('أرفق عقد منصة إيجار بصيغة PDF');
    }
  }

  Map<String, dynamic> toMap() => {
        'contractId': submissionId,
        'idNumber': normalize(idNumber),
        'birthDate': normalize(birthDate),
        'mobile': normalize(mobile),
        'fileName': fileName,
        'fileUrl': fileUrl,
        'sourceContractId': sourceContractId,
      };
}
