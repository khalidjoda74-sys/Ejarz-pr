import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum EjarzProFont { cairo }

enum EjarzProQuickTileStyle { gradient, soft, outline, split, glass }

class EjarzProThemeSpec {
  final String id;
  final String name;
  final String description;
  final EjarzProFont font;
  final EjarzProQuickTileStyle quickTileStyle;
  final Brightness statusBrightness;
  final Color primary;
  final Color secondary;
  final Color accent;
  final Color routeBackground;
  final Color appChrome;
  final Color drawerBackground;
  final Color surface;
  final Color surfaceAlt;
  final Color card;
  final Color cardAlt;
  final Color textPrimary;
  final Color textSecondary;
  final Color border;
  final Color quickStart;
  final Color quickEnd;
  final Color quickSurface;
  final Color quickIconBg;
  final Color quickText;
  final Color glowA;
  final Color glowB;
  final List<Color> homeGradient;

  const EjarzProThemeSpec({
    required this.id,
    required this.name,
    required this.description,
    required this.font,
    required this.quickTileStyle,
    required this.statusBrightness,
    required this.primary,
    required this.secondary,
    required this.accent,
    required this.routeBackground,
    required this.appChrome,
    required this.drawerBackground,
    required this.surface,
    required this.surfaceAlt,
    required this.card,
    required this.cardAlt,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
    required this.quickStart,
    required this.quickEnd,
    required this.quickSurface,
    required this.quickIconBg,
    required this.quickText,
    required this.glowA,
    required this.glowB,
    required this.homeGradient,
  });

  String get fontFamily {
    return GoogleFonts.cairo().fontFamily ?? 'Cairo';
  }

  TextStyle textStyle({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
  }) {
    return GoogleFonts.cairo(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
    );
  }

  ThemeData materialTheme({
    required PageTransitionsTheme pageTransitionsTheme,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: primary,
      secondary: secondary,
      tertiary: accent,
      surface: surface,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: textPrimary,
      outline: border,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: routeBackground,
      canvasColor: routeBackground,
      colorScheme: scheme,
      fontFamily: fontFamily,
      extensions: <ThemeExtension<dynamic>>[
        EjarzProThemeExtension(this),
      ],
      appBarTheme: AppBarTheme(
        backgroundColor: appChrome,
        elevation: 0,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: textStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: appChrome,
          statusBarIconBrightness: statusBrightness,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: appChrome,
        selectedItemColor: accent,
        unselectedItemColor: Colors.white.withOpacity(0.72),
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: appChrome,
        indicatorColor: accent.withOpacity(0.18),
        elevation: 8,
        labelTextStyle: WidgetStateProperty.all(
          textStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        iconTheme: WidgetStateProperty.all(
          const IconThemeData(color: Colors.white),
        ),
      ),
      bottomAppBarTheme: BottomAppBarThemeData(
        color: appChrome,
        elevation: 8,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.all(primary),
          foregroundColor: WidgetStateProperty.all(Colors.white),
          elevation: WidgetStateProperty.all(2),
        ),
      ),
      pageTransitionsTheme: pageTransitionsTheme,
    );
  }
}

class EjarzProThemeExtension extends ThemeExtension<EjarzProThemeExtension> {
  final EjarzProThemeSpec spec;

  const EjarzProThemeExtension(this.spec);

  @override
  EjarzProThemeExtension copyWith({EjarzProThemeSpec? spec}) {
    return EjarzProThemeExtension(spec ?? this.spec);
  }

  @override
  EjarzProThemeExtension lerp(
    ThemeExtension<EjarzProThemeExtension>? other,
    double t,
  ) {
    if (other is! EjarzProThemeExtension) return this;
    return t < 0.5 ? this : other;
  }
}

extension EjarzProThemeContext on BuildContext {
  EjarzProThemeSpec get ejarzProTheme {
    return Theme.of(this).extension<EjarzProThemeExtension>()?.spec ??
        AppThemes.defaultTheme;
  }
}

class AppThemes {
  static const EjarzProThemeSpec oasis = EjarzProThemeSpec(
    id: 'oasis',
    name: '\u0648\u0627\u062d\u0629 \u0625\u064a\u062c\u0627\u0631\u0632',
    description:
        '\u0623\u062e\u0636\u0631 \u0639\u0642\u0627\u0631\u064a \u0647\u0627\u062f\u0626',
    font: EjarzProFont.cairo,
    quickTileStyle: EjarzProQuickTileStyle.gradient,
    statusBrightness: Brightness.light,
    primary: Color(0xFF0F766E),
    secondary: Color(0xFF2563EB),
    accent: Color(0xFF5EEAD4),
    routeBackground: Color(0xFFF6FAF8),
    appChrome: Color(0xFF0F172A),
    drawerBackground: Color(0xFFFFFBEB),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFEFFCF8),
    card: Color(0xFFFFFBEB),
    cardAlt: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF475569),
    border: Color(0x1A0F172A),
    quickStart: Color(0xFF0F766E),
    quickEnd: Color(0xFF14B8A6),
    quickSurface: Color(0xFFFFFFFF),
    quickIconBg: Color(0xFFE6FFFA),
    quickText: Color(0xFFFFFFFF),
    glowA: Color(0x33FFFFFF),
    glowB: Color(0x22FFFFFF),
    homeGradient: [Color(0xFF0F172A), Color(0xFF0F766E), Color(0xFF14B8A6)],
  );

  static const List<EjarzProThemeSpec> all = [
    oasis,
    EjarzProThemeSpec(
      id: 'riyadh_dawn',
      name: '\u0641\u062c\u0631 \u0627\u0644\u0631\u064a\u0627\u0636',
      description:
          '\u0623\u0632\u0631\u0642 \u0647\u0627\u062f\u0626 \u0644\u0644\u0645\u0643\u0627\u062a\u0628',
      font: EjarzProFont.cairo,
      quickTileStyle: EjarzProQuickTileStyle.soft,
      statusBrightness: Brightness.light,
      primary: Color(0xFF2563EB),
      secondary: Color(0xFF0E7490),
      accent: Color(0xFF93C5FD),
      routeBackground: Color(0xFFF7FAFF),
      appChrome: Color(0xFF172554),
      drawerBackground: Color(0xFFF8FBFF),
      surface: Color(0xFFFFFFFF),
      surfaceAlt: Color(0xFFEFF6FF),
      card: Color(0xFFFFFFFF),
      cardAlt: Color(0xFFEFF6FF),
      textPrimary: Color(0xFF0F172A),
      textSecondary: Color(0xFF475569),
      border: Color(0x1F1E3A8A),
      quickStart: Color(0xFF2563EB),
      quickEnd: Color(0xFF0E7490),
      quickSurface: Color(0xFFFFFFFF),
      quickIconBg: Color(0xFFDBEAFE),
      quickText: Color(0xFF172554),
      glowA: Color(0x3393C5FD),
      glowB: Color(0x225EEAD4),
      homeGradient: [Color(0xFF172554), Color(0xFF1D4ED8), Color(0xFF0E7490)],
    ),
    EjarzProThemeSpec(
      id: 'golden_palm',
      name: '\u0646\u062e\u064a\u0644 \u0630\u0647\u0628\u064a',
      description:
          '\u0623\u062e\u0636\u0631 \u0641\u0627\u062e\u0631 \u0645\u0639 \u0630\u0647\u0628\u064a',
      font: EjarzProFont.cairo,
      quickTileStyle: EjarzProQuickTileStyle.outline,
      statusBrightness: Brightness.light,
      primary: Color(0xFF14532D),
      secondary: Color(0xFFB45309),
      accent: Color(0xFFFACC15),
      routeBackground: Color(0xFFF9FAF3),
      appChrome: Color(0xFF14342B),
      drawerBackground: Color(0xFFFFFCF1),
      surface: Color(0xFFFFFFFF),
      surfaceAlt: Color(0xFFF1F8E9),
      card: Color(0xFFFFFCF1),
      cardAlt: Color(0xFFFFFFFF),
      textPrimary: Color(0xFF13261E),
      textSecondary: Color(0xFF58665E),
      border: Color(0x2614532D),
      quickStart: Color(0xFF14532D),
      quickEnd: Color(0xFFB45309),
      quickSurface: Color(0xFFFFFCF1),
      quickIconBg: Color(0xFFECFCCB),
      quickText: Color(0xFF14342B),
      glowA: Color(0x33FACC15),
      glowB: Color(0x2216A34A),
      homeGradient: [Color(0xFF14342B), Color(0xFF166534), Color(0xFFB45309)],
    ),
    EjarzProThemeSpec(
      id: 'cloud',
      name: '\u0633\u062d\u0627\u0628\u0629',
      description:
          '\u0641\u0627\u062a\u062d \u0648\u0645\u0631\u064a\u062d \u0644\u0644\u0642\u0631\u0627\u0621\u0629',
      font: EjarzProFont.cairo,
      quickTileStyle: EjarzProQuickTileStyle.soft,
      statusBrightness: Brightness.light,
      primary: Color(0xFF334155),
      secondary: Color(0xFF0891B2),
      accent: Color(0xFFA7F3D0),
      routeBackground: Color(0xFFF8FAFC),
      appChrome: Color(0xFF1F2937),
      drawerBackground: Color(0xFFFFFFFF),
      surface: Color(0xFFFFFFFF),
      surfaceAlt: Color(0xFFF1F5F9),
      card: Color(0xFFFFFFFF),
      cardAlt: Color(0xFFF8FAFC),
      textPrimary: Color(0xFF111827),
      textSecondary: Color(0xFF64748B),
      border: Color(0x1F334155),
      quickStart: Color(0xFF334155),
      quickEnd: Color(0xFF0891B2),
      quickSurface: Color(0xFFFFFFFF),
      quickIconBg: Color(0xFFE0F2FE),
      quickText: Color(0xFF111827),
      glowA: Color(0x33E0F2FE),
      glowB: Color(0x22FFFFFF),
      homeGradient: [Color(0xFF334155), Color(0xFF64748B), Color(0xFF0891B2)],
    ),
    EjarzProThemeSpec(
      id: 'emerald',
      name: '\u0632\u0645\u0631\u062f',
      description: '\u062d\u062f\u064a\u062b \u0648\u0648\u0627\u0636\u062d',
      font: EjarzProFont.cairo,
      quickTileStyle: EjarzProQuickTileStyle.split,
      statusBrightness: Brightness.light,
      primary: Color(0xFF047857),
      secondary: Color(0xFF0F766E),
      accent: Color(0xFF34D399),
      routeBackground: Color(0xFFF0FDF4),
      appChrome: Color(0xFF064E3B),
      drawerBackground: Color(0xFFF0FDF4),
      surface: Color(0xFFFFFFFF),
      surfaceAlt: Color(0xFFD1FAE5),
      card: Color(0xFFECFDF5),
      cardAlt: Color(0xFFFFFFFF),
      textPrimary: Color(0xFF052E2B),
      textSecondary: Color(0xFF3F625B),
      border: Color(0x26047857),
      quickStart: Color(0xFF047857),
      quickEnd: Color(0xFF34D399),
      quickSurface: Color(0xFFFFFFFF),
      quickIconBg: Color(0xFFD1FAE5),
      quickText: Color(0xFF052E2B),
      glowA: Color(0x3334D399),
      glowB: Color(0x220F766E),
      homeGradient: [Color(0xFF064E3B), Color(0xFF047857), Color(0xFF34D399)],
    ),
    EjarzProThemeSpec(
      id: 'harbor',
      name: '\u0645\u0631\u0633\u0649',
      description:
          '\u0643\u062d\u0644\u064a \u0645\u0639 \u062a\u0631\u0643\u0648\u0627\u0632',
      font: EjarzProFont.cairo,
      quickTileStyle: EjarzProQuickTileStyle.glass,
      statusBrightness: Brightness.light,
      primary: Color(0xFF0E7490),
      secondary: Color(0xFF155E75),
      accent: Color(0xFF67E8F9),
      routeBackground: Color(0xFFF0FDFA),
      appChrome: Color(0xFF0F2F3A),
      drawerBackground: Color(0xFFF5FEFF),
      surface: Color(0xFFFFFFFF),
      surfaceAlt: Color(0xFFCFFAFE),
      card: Color(0xFFEFFDFD),
      cardAlt: Color(0xFFFFFFFF),
      textPrimary: Color(0xFF0F172A),
      textSecondary: Color(0xFF475569),
      border: Color(0x260E7490),
      quickStart: Color(0xFF155E75),
      quickEnd: Color(0xFF0E7490),
      quickSurface: Color(0x2EFFFFFF),
      quickIconBg: Color(0x3367E8F9),
      quickText: Color(0xFFFFFFFF),
      glowA: Color(0x3367E8F9),
      glowB: Color(0x2200B4D8),
      homeGradient: [Color(0xFF0F2F3A), Color(0xFF155E75), Color(0xFF0E7490)],
    ),
    EjarzProThemeSpec(
      id: 'pearl',
      name: '\u0644\u0624\u0644\u0624',
      description:
          '\u0623\u0628\u064a\u0636 \u0646\u0627\u0639\u0645 \u0648\u0623\u0646\u064a\u0642',
      font: EjarzProFont.cairo,
      quickTileStyle: EjarzProQuickTileStyle.outline,
      statusBrightness: Brightness.light,
      primary: Color(0xFF475569),
      secondary: Color(0xFF0F766E),
      accent: Color(0xFFCBD5E1),
      routeBackground: Color(0xFFFBFCFD),
      appChrome: Color(0xFF263445),
      drawerBackground: Color(0xFFFBFCFD),
      surface: Color(0xFFFFFFFF),
      surfaceAlt: Color(0xFFF3F6F8),
      card: Color(0xFFFFFFFF),
      cardAlt: Color(0xFFF8FAFC),
      textPrimary: Color(0xFF1F2937),
      textSecondary: Color(0xFF667085),
      border: Color(0x1F475569),
      quickStart: Color(0xFF475569),
      quickEnd: Color(0xFF0F766E),
      quickSurface: Color(0xFFFFFFFF),
      quickIconBg: Color(0xFFEFF4F7),
      quickText: Color(0xFF1F2937),
      glowA: Color(0x33FFFFFF),
      glowB: Color(0x22CBD5E1),
      homeGradient: [Color(0xFF263445), Color(0xFF475569), Color(0xFF0F766E)],
    ),
    EjarzProThemeSpec(
      id: 'pomegranate',
      name: '\u0631\u0645\u0627\u0646',
      description:
          '\u0639\u0646\u0627\u0628\u064a \u0647\u0627\u062f\u0626 \u0648\u0645\u062e\u062a\u0644\u0641',
      font: EjarzProFont.cairo,
      quickTileStyle: EjarzProQuickTileStyle.split,
      statusBrightness: Brightness.light,
      primary: Color(0xFF9F1239),
      secondary: Color(0xFF0F766E),
      accent: Color(0xFFFDA4AF),
      routeBackground: Color(0xFFFFF7F8),
      appChrome: Color(0xFF4C1022),
      drawerBackground: Color(0xFFFFF7F8),
      surface: Color(0xFFFFFFFF),
      surfaceAlt: Color(0xFFFFE4E6),
      card: Color(0xFFFFF1F2),
      cardAlt: Color(0xFFFFFFFF),
      textPrimary: Color(0xFF24111A),
      textSecondary: Color(0xFF6B4A57),
      border: Color(0x269F1239),
      quickStart: Color(0xFF9F1239),
      quickEnd: Color(0xFFBE123C),
      quickSurface: Color(0xFFFFFFFF),
      quickIconBg: Color(0xFFFFE4E6),
      quickText: Color(0xFF24111A),
      glowA: Color(0x33FDA4AF),
      glowB: Color(0x2214B8A6),
      homeGradient: [Color(0xFF4C1022), Color(0xFF9F1239), Color(0xFF0F766E)],
    ),
    EjarzProThemeSpec(
      id: 'office_night',
      name: '\u0644\u064a\u0644 \u0645\u0643\u062a\u0628\u064a',
      description:
          '\u062f\u0627\u0643\u0646 \u0645\u0631\u064a\u062d \u0648\u0627\u062d\u062a\u0631\u0627\u0641\u064a',
      font: EjarzProFont.cairo,
      quickTileStyle: EjarzProQuickTileStyle.glass,
      statusBrightness: Brightness.light,
      primary: Color(0xFF22C55E),
      secondary: Color(0xFF38BDF8),
      accent: Color(0xFFA7F3D0),
      routeBackground: Color(0xFF101826),
      appChrome: Color(0xFF0B1220),
      drawerBackground: Color(0xFF101826),
      surface: Color(0xFF182235),
      surfaceAlt: Color(0xFF1F2A3D),
      card: Color(0xFF172033),
      cardAlt: Color(0xFF202B3E),
      textPrimary: Color(0xFFF8FAFC),
      textSecondary: Color(0xFFCBD5E1),
      border: Color(0x33FFFFFF),
      quickStart: Color(0xFF22C55E),
      quickEnd: Color(0xFF38BDF8),
      quickSurface: Color(0x22172033),
      quickIconBg: Color(0x3322C55E),
      quickText: Color(0xFFFFFFFF),
      glowA: Color(0x3338BDF8),
      glowB: Color(0x2222C55E),
      homeGradient: [Color(0xFF0B1220), Color(0xFF172033), Color(0xFF0F766E)],
    ),
    EjarzProThemeSpec(
      id: 'clarity',
      name: '\u0635\u0641\u0627\u0621',
      description: '\u0646\u0638\u064a\u0641 \u0648\u062d\u062f\u064a\u062b',
      font: EjarzProFont.cairo,
      quickTileStyle: EjarzProQuickTileStyle.gradient,
      statusBrightness: Brightness.light,
      primary: Color(0xFF0D9488),
      secondary: Color(0xFF0284C7),
      accent: Color(0xFF7DD3FC),
      routeBackground: Color(0xFFF7FEFF),
      appChrome: Color(0xFF12343B),
      drawerBackground: Color(0xFFF7FEFF),
      surface: Color(0xFFFFFFFF),
      surfaceAlt: Color(0xFFE0F2FE),
      card: Color(0xFFFFFFFF),
      cardAlt: Color(0xFFEFFAFE),
      textPrimary: Color(0xFF102A43),
      textSecondary: Color(0xFF486581),
      border: Color(0x1F0D9488),
      quickStart: Color(0xFF0D9488),
      quickEnd: Color(0xFF0284C7),
      quickSurface: Color(0xFFFFFFFF),
      quickIconBg: Color(0xFFE0F2FE),
      quickText: Color(0xFFFFFFFF),
      glowA: Color(0x337DD3FC),
      glowB: Color(0x220D9488),
      homeGradient: [Color(0xFF12343B), Color(0xFF0D9488), Color(0xFF0284C7)],
    ),
  ];

  static const EjarzProThemeSpec defaultTheme = oasis;

  static EjarzProThemeSpec byId(String? id) {
    return all.firstWhere(
      (theme) => theme.id == id,
      orElse: () => defaultTheme,
    );
  }
}

class AppThemeController {
  static const String _prefsKey = 'ejarz_pro_theme_id_v1';
  static final ValueNotifier<EjarzProThemeSpec> current =
      ValueNotifier<EjarzProThemeSpec>(AppThemes.defaultTheme);

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      current.value = AppThemes.byId(prefs.getString(_prefsKey));
    } catch (_) {
      current.value = AppThemes.defaultTheme;
    }
  }

  static Future<void> setTheme(String id) async {
    final next = AppThemes.byId(id);
    current.value = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, next.id);
    } catch (_) {}
  }
}

Future<void> showEjarzProThemePicker(BuildContext context) async {
  final theme = context.ejarzProTheme;
  await showModalBottomSheet(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: theme.surface,
    barrierColor: Colors.black54,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (sheetContext) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: ValueListenableBuilder<EjarzProThemeSpec>(
          valueListenable: AppThemeController.current,
          builder: (context, selected, _) {
            final sheetTheme = selected;
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.78,
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 5,
                        decoration: BoxDecoration(
                          color: sheetTheme.textSecondary.withOpacity(0.24),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: sheetTheme.quickIconBg,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.palette_rounded,
                            color: sheetTheme.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '\u0627\u0644\u062a\u0635\u0645\u064a\u0645',
                            style: sheetTheme.textStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              color: sheetTheme.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: AppThemes.all.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final option = AppThemes.all[index];
                          final isSelected = selected.id == option.id;
                          return _ThemeOptionTile(
                            theme: option,
                            selected: isSelected,
                            onTap: () => AppThemeController.setTheme(option.id),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    },
  );
}

class _ThemeOptionTile extends StatelessWidget {
  final EjarzProThemeSpec theme;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeOptionTile({
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.cardAlt,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? theme.primary : theme.border,
              width: selected ? 1.4 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              _ThemeSwatch(theme: theme),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      theme.name,
                      style: theme.textStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: theme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      theme.description,
                      style: theme.textStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: theme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: selected ? theme.primary : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? theme.primary : theme.border,
                  ),
                ),
                child: selected
                    ? const Icon(Icons.check_rounded,
                        color: Colors.white, size: 18)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  final EjarzProThemeSpec theme;

  const _ThemeSwatch({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: theme.homeGradient,
        ),
      ),
      child: Align(
        alignment: Alignment.bottomLeft,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Dot(color: theme.accent),
              _Dot(color: theme.card),
              _Dot(color: theme.secondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;

  const _Dot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      margin: const EdgeInsetsDirectional.only(start: 3),
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.60), width: 0.6),
      ),
    );
  }
}
