import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_sizes.dart';

class AppTextStyles {
  const AppTextStyles._();

  static const String fontFamily = 'Dubai';
  static const List<String> fontFamilyFallback = <String>[
    'Cairo',
    'Tajawal',
    'Noto Sans Arabic',
    'Segoe UI',
    'Roboto',
    'Arial',
  ];

  static const TextStyle headline = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: AppSizes.baseBigTitleFont,
    fontWeight: FontWeight.w900,
    color: AppColors.textDark,
    height: 1.32,
    letterSpacing: 0,
  );

  static const TextStyle pageTitle = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: AppSizes.basePageTitleFont,
    fontWeight: FontWeight.w800,
    color: AppColors.textDark,
    height: 1.35,
    letterSpacing: 0,
  );

  static const TextStyle cardTitle = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: AppSizes.baseCardTitleFont,
    fontWeight: FontWeight.w800,
    color: AppColors.textDark,
    height: 1.4,
    letterSpacing: 0,
  );

  static const TextStyle body = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: AppSizes.baseBodyFont,
    fontWeight: FontWeight.w500,
    color: AppColors.textDark,
    height: 1.55,
    letterSpacing: 0,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: AppSizes.baseCaptionFont,
    fontWeight: FontWeight.w500,
    color: AppColors.textGray,
    height: 1.45,
    letterSpacing: 0,
  );

  static const TextStyle button = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: AppSizes.baseBodyFont,
    fontWeight: FontWeight.w800,
    color: AppColors.cardWhite,
    height: 1.25,
    letterSpacing: 0,
  );

  static const TextStyle navLabel = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: AppSizes.baseBottomNavLabel,
    fontWeight: FontWeight.w700,
    color: AppColors.textGray,
    height: 1.15,
    letterSpacing: 0,
  );

  static const TextStyle display = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: AppSizes.baseBigTitleFont,
    fontWeight: FontWeight.w900,
    color: AppColors.primaryDarkGreen,
    height: 1.22,
    letterSpacing: 0,
  );

  static const TextStyle h1 = headline;
  static const TextStyle h2 = pageTitle;
  static const TextStyle h3 = cardTitle;
  static const TextStyle small = caption;
}
