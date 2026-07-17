import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFF08795D);
  static const Color primaryDark = Color(0xFF005E49);
  static const Color primaryLight = Color(0xFFE7F5F0);
  static const Color secondary = Color(0xFFD4A53B);
  static const Color secondaryLight = Color(0xFFFFF5DD);
  static const Color background = Color(0xFFFCFBF8);
  static const Color surface = Colors.white;
  static const Color text = Color(0xFF24282B);
  static const Color muted = Color(0xFF7A8084);
  static const Color border = Color(0xFFE7E9E8);
  static const Color blue = Color(0xFF2F73E0);
  static const Color orange = Color(0xFFE99015);
  static const Color red = Color(0xFFC94B4B);
  static const Color success = Color(0xFF16875E);
}

class AppTheme {
  static const String fontFamily = 'IBM Plex Sans Arabic';
  static const List<String> fontFallback = <String>[
    'IBM Plex Sans Arabic',
    'Dubai',
    'Tahoma',
    'Arial',
    'sans-serif',
  ];
  static const String _fontFamily = fontFamily;
  static const List<String> _fontFallback = fontFallback;

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
      primary: AppColors.primary,
      secondary: AppColors.secondary,
      surface: AppColors.surface,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      visualDensity: VisualDensity.compact,
      fontFamily: _fontFamily,
      fontFamilyFallback: _fontFallback,
    );

    return base.copyWith(
      textTheme: base.textTheme
          .copyWith(
            headlineLarge: const TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w800,
              height: 1.25,
              color: AppColors.text,
            ),
            headlineMedium: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.28,
              color: AppColors.text,
            ),
            headlineSmall: const TextStyle(
              fontSize: 18.5,
              fontWeight: FontWeight.w800,
              height: 1.3,
              color: AppColors.text,
            ),
            titleLarge: const TextStyle(
              fontSize: 16.5,
              fontWeight: FontWeight.w800,
              height: 1.3,
              color: AppColors.text,
            ),
            titleMedium: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              height: 1.4,
              color: AppColors.text,
            ),
            bodyLarge: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.55,
              color: AppColors.text,
            ),
            bodyMedium: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.5,
              color: AppColors.text,
            ),
            bodySmall: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              height: 1.45,
              color: AppColors.muted,
            ),
            labelLarge: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          )
          .apply(
            fontFamily: _fontFamily,
            fontFamilyFallback: _fontFallback,
            bodyColor: AppColors.text,
            displayColor: AppColors.text,
          ),
      appBarTheme: const AppBarTheme(
        toolbarHeight: 48,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.text,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: AppColors.primary,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          fontFamily: _fontFamily,
          fontFamilyFallback: _fontFallback,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        hintStyle: const TextStyle(
          color: Color(0xFFA4A8AA),
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
          fontFamily: _fontFamily,
          fontFamilyFallback: _fontFallback,
        ),
        labelStyle: const TextStyle(
          color: AppColors.text,
          fontWeight: FontWeight.w700,
          fontFamily: _fontFamily,
          fontFamilyFallback: _fontFallback,
        ),
        prefixIconColor: AppColors.muted,
        suffixIconColor: AppColors.muted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.red),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(44),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            fontFamily: _fontFamily,
            fontFamilyFallback: _fontFallback,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size.fromHeight(44),
          side: const BorderSide(color: AppColors.primary, width: 1.2),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            fontFamily: _fontFamily,
            fontFamilyFallback: _fontFallback,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            fontFamily: _fontFamily,
            fontFamilyFallback: _fontFallback,
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 56,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 10.5,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w600,
            fontFamily: _fontFamily,
            fontFamilyFallback: _fontFallback,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: states.contains(WidgetState.selected) ? 22 : 21,
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        side: const BorderSide(color: AppColors.border),
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontFamily: _fontFamily,
          fontFamilyFallback: _fontFallback,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.primaryDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontFamily: _fontFamily,
          fontFamilyFallback: _fontFallback,
        ),
      ),
    );
  }

  static ThemeData dark() {
    final lightTheme = light();
    const background = Color(0xFF111816);
    const surface = Color(0xFF17211E);
    const border = Color(0xFF2B3733);
    const text = Color(0xFFF5F7F6);
    const muted = Color(0xFFA7B0AC);

    return lightTheme.copyWith(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: lightTheme.colorScheme.copyWith(
        brightness: Brightness.dark,
        surface: surface,
        onSurface: text,
      ),
      appBarTheme: lightTheme.appBarTheme.copyWith(
        backgroundColor: background,
        foregroundColor: text,
      ),
      cardColor: surface,
      dividerTheme: const DividerThemeData(color: border, thickness: 1),
      textTheme:
          lightTheme.textTheme.apply(bodyColor: text, displayColor: text),
      inputDecorationTheme: lightTheme.inputDecorationTheme.copyWith(
        fillColor: surface,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(backgroundColor: surface),
      drawerTheme: const DrawerThemeData(backgroundColor: surface),
      snackBarTheme: lightTheme.snackBarTheme,
      extensions: const <ThemeExtension<dynamic>>[
        EjarzThemeExtension(
          background: background,
          surface: surface,
          border: border,
          text: text,
          muted: muted,
        ),
      ],
    );
  }
}

@immutable
class EjarzThemeExtension extends ThemeExtension<EjarzThemeExtension> {
  final Color background;
  final Color surface;
  final Color border;
  final Color text;
  final Color muted;

  const EjarzThemeExtension({
    required this.background,
    required this.surface,
    required this.border,
    required this.text,
    required this.muted,
  });

  @override
  EjarzThemeExtension copyWith({
    Color? background,
    Color? surface,
    Color? border,
    Color? text,
    Color? muted,
  }) {
    return EjarzThemeExtension(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      border: border ?? this.border,
      text: text ?? this.text,
      muted: muted ?? this.muted,
    );
  }

  @override
  EjarzThemeExtension lerp(
      ThemeExtension<EjarzThemeExtension>? other, double t) {
    if (other is! EjarzThemeExtension) return this;
    return EjarzThemeExtension(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      border: Color.lerp(border, other.border, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
    );
  }
}

extension ThemeContextX on BuildContext {
  EjarzThemeExtension get ejarzTheme {
    return Theme.of(this).extension<EjarzThemeExtension>() ??
        const EjarzThemeExtension(
          background: AppColors.background,
          surface: AppColors.surface,
          border: AppColors.border,
          text: AppColors.text,
          muted: AppColors.muted,
        );
  }

  double get screenWidth => MediaQuery.sizeOf(this).width;
  double get screenHeight => MediaQuery.sizeOf(this).height;

  double sp(double base) {
    final scale = (screenWidth / 390).clamp(0.90, 1.12);
    return base * scale;
  }

  double gap(double base) {
    final scale = (screenWidth / 390).clamp(0.88, 1.15);
    return base * scale;
  }
}

BoxDecoration appCardDecoration(
  BuildContext context, {
  Color? color,
  double radius = 20,
  Border? border,
  List<BoxShadow>? shadows,
}) {
  final ext = context.ejarzTheme;
  return BoxDecoration(
    color: color ?? ext.surface,
    borderRadius: BorderRadius.circular(radius),
    border: border ?? Border.all(color: ext.border),
    boxShadow: shadows ??
        <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(
              alpha: Theme.of(context).brightness == Brightness.dark
                  ? 0.20
                  : 0.055,
            ),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
  );
}
