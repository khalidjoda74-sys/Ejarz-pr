import 'package:flutter/widgets.dart';

class AppSizes {
  const AppSizes._(this.scale);

  factory AppSizes.of(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final scale = (width / referenceWidth).clamp(minScale, maxScale).toDouble();
    return AppSizes._(scale);
  }

  static const AppSizes base = AppSizes._(1);

  static const double minScale = .90;
  static const double maxScale = 1.06;
  static const double referenceWidth = 390;

  static const double baseHorizontalPadding = 12;
  static const double baseCardRadius = 20;
  static const double baseSmallRadius = 12;
  static const double baseCardPadding = 14;
  static const double baseSectionSpacing = 14;
  static const double baseItemSpacing = 10;
  static const double baseHeaderHeight = 112;
  static const double baseInnerHeaderHeight = 124;
  static const double baseBottomNavHeight = 68;
  static const double baseBottomNavIcon = 24;
  static const double baseBottomNavLabel = 12.4;
  static const double baseCenterAddButton = 54;
  static const double baseCardTitleFont = 15;
  static const double baseBodyFont = 13;
  static const double baseCaptionFont = 11;
  static const double basePageTitleFont = 17;
  static const double baseBigTitleFont = 22;

  final double scale;

  double value(double baseValue) => baseValue * scale;

  double get horizontalPadding => value(baseHorizontalPadding);
  double get cardRadius => value(baseCardRadius);
  double get smallRadius => value(baseSmallRadius);
  double get cardPadding => value(baseCardPadding);
  double get sectionSpacing => value(baseSectionSpacing);
  double get itemSpacing => value(baseItemSpacing);
  double get headerHeight => value(baseHeaderHeight);
  double get innerHeaderHeight => value(baseInnerHeaderHeight);
  double get bottomNavHeight => value(baseBottomNavHeight);
  double get bottomNavIcon => value(baseBottomNavIcon);
  double get bottomNavLabel => value(baseBottomNavLabel);
  double get centerAddButton => value(baseCenterAddButton);
  double get cardTitleFont => value(baseCardTitleFont);
  double get bodyFont => value(baseBodyFont);
  double get captionFont => value(baseCaptionFont);
  double get pageTitleFont => value(basePageTitleFont);
  double get bigTitleFont => value(baseBigTitleFont);
}
