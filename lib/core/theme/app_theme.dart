import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_sizes.dart';
import 'app_text_styles.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: AppTextStyles.fontFamily,
      fontFamilyFallback: AppTextStyles.fontFamilyFallback,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primaryDarkGreen,
        brightness: Brightness.light,
      ).copyWith(
        primary: AppColors.primaryDarkGreen,
        onPrimary: AppColors.cardWhite,
        secondary: AppColors.primaryGreen,
        onSecondary: AppColors.cardWhite,
        tertiary: AppColors.gold,
        onTertiary: AppColors.textDark,
        error: AppColors.red,
        onError: AppColors.cardWhite,
        surface: AppColors.cardWhite,
        onSurface: AppColors.textDark,
        outline: AppColors.borderBeige,
      ),
      textTheme: _textTheme,
    );

    return base.copyWith(
      primaryColor: AppColors.primaryDarkGreen,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _MajalisnaPageTransitionsBuilder(),
          TargetPlatform.fuchsia: _MajalisnaPageTransitionsBuilder(),
          TargetPlatform.iOS: _MajalisnaPageTransitionsBuilder(),
          TargetPlatform.linux: _MajalisnaPageTransitionsBuilder(),
          TargetPlatform.macOS: _MajalisnaPageTransitionsBuilder(),
          TargetPlatform.windows: _MajalisnaPageTransitionsBuilder(),
        },
      ),
      appBarTheme: const AppBarThemeData(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.cardWhite,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: AppTextStyles.pageTitle,
      ),
      cardTheme: CardThemeData(
        color: AppColors.cardWhite,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.base.cardRadius),
          side: const BorderSide(color: AppColors.borderBeige),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.cardWhite,
        selectedColor: AppColors.primaryDarkGreen,
        disabledColor: AppColors.borderBeige,
        secondarySelectedColor: AppColors.primaryGreen,
        labelStyle: AppTextStyles.caption.copyWith(color: AppColors.textDark),
        secondaryLabelStyle:
            AppTextStyles.caption.copyWith(color: AppColors.cardWhite),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: const BorderSide(color: AppColors.borderBeige),
        ),
        side: const BorderSide(color: AppColors.borderBeige),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.borderBeige,
        thickness: 1,
        space: 1,
      ),
      iconTheme: const IconThemeData(
        color: AppColors.primaryDarkGreen,
        size: 21,
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: AppColors.cardWhite,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        hintStyle: AppTextStyles.caption,
        labelStyle: AppTextStyles.body,
        errorStyle: AppTextStyles.caption.copyWith(color: AppColors.red),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.base.smallRadius),
          borderSide: const BorderSide(color: AppColors.borderBeige),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.base.smallRadius),
          borderSide: const BorderSide(color: AppColors.borderBeige),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.base.smallRadius),
          borderSide:
              const BorderSide(color: AppColors.primaryGreen, width: 1.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.base.smallRadius),
          borderSide: const BorderSide(color: AppColors.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.base.smallRadius),
          borderSide: const BorderSide(color: AppColors.red, width: 1.2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: AppColors.primaryDarkGreen,
          foregroundColor: AppColors.cardWhite,
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.base.smallRadius),
          ),
          textStyle: AppTextStyles.button,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryDarkGreen,
          minimumSize: const Size.fromHeight(44),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          side: const BorderSide(color: AppColors.borderBeige),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.base.smallRadius),
          ),
          textStyle:
              AppTextStyles.button.copyWith(color: AppColors.primaryDarkGreen),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryGreen,
          textStyle:
              AppTextStyles.button.copyWith(color: AppColors.primaryGreen),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.cardWhite,
        selectedItemColor: AppColors.primaryDarkGreen,
        unselectedItemColor: AppColors.textGray,
        selectedIconTheme: IconThemeData(size: AppSizes.baseBottomNavIcon),
        unselectedIconTheme: IconThemeData(size: AppSizes.baseBottomNavIcon),
        selectedLabelStyle: AppTextStyles.navLabel,
        unselectedLabelStyle: AppTextStyles.navLabel,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
    );
  }

  static const TextTheme _textTheme = TextTheme(
    displayLarge: AppTextStyles.headline,
    displayMedium: AppTextStyles.headline,
    displaySmall: AppTextStyles.pageTitle,
    headlineLarge: AppTextStyles.headline,
    headlineMedium: AppTextStyles.pageTitle,
    headlineSmall: AppTextStyles.pageTitle,
    titleLarge: AppTextStyles.pageTitle,
    titleMedium: AppTextStyles.cardTitle,
    titleSmall: AppTextStyles.cardTitle,
    bodyLarge: AppTextStyles.body,
    bodyMedium: AppTextStyles.body,
    bodySmall: AppTextStyles.caption,
    labelLarge: AppTextStyles.button,
    labelMedium: AppTextStyles.navLabel,
    labelSmall: AppTextStyles.caption,
  );
}

class _MajalisnaPageTransitionsBuilder extends PageTransitionsBuilder {
  const _MajalisnaPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (route.isFirst) {
      return ColoredBox(color: AppColors.background, child: child);
    }

    final direction = Directionality.maybeOf(context) ?? TextDirection.rtl;
    final beginOffset =
        Offset(direction == TextDirection.rtl ? -0.025 : 0.025, 0);
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return ColoredBox(
      color: AppColors.background,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: route.fullscreenDialog ? Offset.zero : beginOffset,
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
