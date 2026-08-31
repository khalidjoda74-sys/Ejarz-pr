String digitsOnly(String value) => value.replaceAll(RegExp(r'\D'), '');

String? validateContractIdentityNumber(String? value, String idType) {
  final cleaned = (value ?? '').trim();
  if (cleaned.isEmpty) return 'هذا الحقل مطلوب';
  final digits = digitsOnly(cleaned);
  if (idType == 'هوية وطنية') {
    if (digits.length == 10 && digits.startsWith('1')) return null;
    return 'الهوية الوطنية يجب أن تكون 10 أرقام وتبدأ بـ 1';
  }
  if (idType == 'إقامة') {
    if (digits.length == 10 && digits.startsWith('2')) return null;
    return 'رقم الإقامة يجب أن يكون 10 أرقام ويبدأ بـ 2';
  }
  if (idType == 'هوية خليجية') {
    if (digits.length >= 8 && digits.length <= 15) return null;
    return 'أدخل رقم هوية خليجية صحيحًا';
  }
  if (cleaned.length >= 6 && cleaned.length <= 15) return null;
  return 'أدخل رقم جواز صحيحًا من 6 إلى 15 خانة';
}

DateTime adultBirthDateCutoff({DateTime? today}) {
  final current = today ?? DateTime.now();
  return DateTime(current.year - 18, current.month, current.day);
}

String? validateAdultBirthDate(String? value, {DateTime? today}) {
  final cleaned = value?.trim() ?? '';
  if (cleaned.isEmpty) return 'هذا الحقل مطلوب';
  final parts = cleaned.split(RegExp(r'[/\-]'));
  if (parts.length != 3) return 'أدخل تاريخ ميلاد صحيحًا';
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) {
    return 'أدخل تاريخ ميلاد صحيحًا';
  }
  final birthDate = DateTime(year, month, day);
  if (birthDate.year != year ||
      birthDate.month != month ||
      birthDate.day != day ||
      year < 1900) {
    return 'أدخل تاريخ ميلاد صحيحًا';
  }
  if (birthDate.isAfter(adultBirthDateCutoff(today: today))) {
    return 'يجب أن يكون العمر 18 سنة مكتملة على الأقل';
  }
  return null;
}
