/// All amounts are package prices in SAR, inclusive of Ejar platform fees.
class ContractPrice {
  final double firstYear;
  final double additionalYearRate;
  final double additionalYears;

  const ContractPrice(
      {required this.firstYear,
      required this.additionalYearRate,
      required this.additionalYears});

  double get additionalAmount => _money(additionalYearRate * additionalYears);
  double get total => _money(firstYear + additionalAmount);

  static double _money(double value) => (value * 100).round() / 100;

  static ContractPrice calculate(
      {required bool commercial, int years = 1, int months = 0, int days = 0}) {
    final duration = years + months / 12 + days / 365;
    return ContractPrice(
      firstYear: commercial ? 399 : 299,
      additionalYearRate: commercial ? 400 : 125,
      additionalYears: (duration - 1).clamp(0, double.infinity),
    );
  }

  static const inclusionNote = 'الأسعار شاملة رسوم منصة إيجار';
  static const durationNote =
      'تُطبق رسوم السنة الأولى على المدد حتى سنة. تُحسب المدة الإضافية بالتناسب: الشهر 1/12 من السنة واليوم 1/365 منها.';
}
