/// Money is computed in halalas. AI output never supplies calculated totals.
class RentalCalculation {
  final int months;
  final int totalHalalas;
  final List<int> installments;
  const RentalCalculation(this.months, this.totalHalalas, this.installments);
}

class ContractCalculationEngine {
  static int _roundRatio(int amount, int multiplier, int denominator) =>
      ((BigInt.from(amount) * BigInt.from(multiplier) +
                  BigInt.from(denominator ~/ 2)) ~/
              BigInt.from(denominator))
          .toInt();
  static String normalizeDigits(String value) {
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    for (var i = 0; i < 10; i++) {
      value = value.replaceAll(arabic[i], '$i').replaceAll(persian[i], '$i');
    }
    return value.replaceAll('٫', '.').replaceAll('٬', ',');
  }

  static int? money(String value) {
    final text = normalizeDigits(value).replaceAll(',', '').trim();
    if (!RegExp(r'^\d{1,10}(\.\d{1,2})?$').hasMatch(text)) return null;
    final parts = text.split('.');
    return int.parse(parts.first) * 100 +
        (parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0')));
  }

  static String amount(int halalas) =>
      '${halalas ~/ 100}.${(halalas % 100).toString().padLeft(2, '0')}';

  static DateTime? date(String value) {
    final parts = normalizeDigits(value).split(RegExp(r'[/\-]'));
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null || y < 1900 || y > 2200) {
      return null;
    }
    final result = DateTime.utc(y, m, d);
    return result.year == y && result.month == m && result.day == d
        ? result
        : null;
  }

  static DateTime addMonths(DateTime start, int months) {
    final first = DateTime.utc(start.year, start.month + months);
    final lastDay = DateTime.utc(first.year, first.month + 1, 0).day;
    return DateTime.utc(first.year, first.month, start.day.clamp(1, lastDay));
  }

  static String formatDate(DateTime date) =>
      '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';

  static int frequencyMonths(String frequency) => switch (frequency) {
        'شهري' => 1,
        'ربع سنوي' => 3,
        'نصف سنوي' => 6,
        'سنوي' => 12,
        _ => throw const FormatException('دورية دفع غير معروفة'),
      };

  /// Extra days use the explicitly displayed annual/365 convention.
  /// Last installment absorbs rounding so its sum always equals the total.
  static RentalCalculation calculate(
      {required int annualHalalas,
      required int years,
      int months = 0,
      int days = 0,
      int frequencyMonths = 3,
      int? customCount,
      bool singlePayment = false}) {
    final totalMonths = years * 12 + months;
    if (annualHalalas <= 0 ||
        years < 0 ||
        months < 0 ||
        days < 0 ||
        totalMonths > 1200 ||
        days > 366 ||
        totalMonths + days <= 0 ||
        frequencyMonths < 1 ||
        frequencyMonths > 12) {
      throw const FormatException('مدة أو قيمة إيجار غير صالحة');
    }
    final total =
        _roundRatio(annualHalalas, totalMonths * 365 + days * 12, 12 * 365);
    final count = singlePayment
        ? 1
        : customCount ??
            ((totalMonths + (days > 0 ? 1 : 0)) / frequencyMonths).ceil();
    if (count < 1 || count > 1200) {
      throw const FormatException('عدد دفعات غير صالح');
    }
    final values = <int>[];
    var allocated = 0;
    for (var i = 0; i < count; i++) {
      final cumulative = singlePayment || customCount != null
          ? _roundRatio(total, i + 1, count)
          : i == count - 1
              ? total
              : _roundRatio(annualHalalas,
                  ((i + 1) * frequencyMonths).clamp(0, totalMonths), 12);
      values.add(cumulative - allocated);
      allocated = cumulative;
    }
    return RentalCalculation(totalMonths, total, values);
  }
}
