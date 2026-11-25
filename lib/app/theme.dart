import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Brand tokens ported from outstagram-web `src/index.css` (dark is the default, as on the web).
abstract final class Brand {
  // dark
  static const night = Color(0xFF0F0F23);
  static const nightCard = Color(0xFF1A1D3A);
  static const nightRaised = Color(0xFF2A2D5A);
  static const neon = Color(0xFF00FF88);
  static const volt = Color(0xFFFFFF00);
  // light
  static const paper = Color(0xFFF6F7FB);
  static const ink = Color(0xFF12142B);
  static const emerald = Color(0xFF047857);
  static const amber = Color(0xFFB45309);
  static const mist = Color(0xFFE8EAF4);
  // logo kit (../assets/README.txt): for images that must look the same in both themes (result cards)
  static const logoNavy = Color(0xFF101020);
  // streak freeze (frozen days in the streak calendar)
  static const ice = Color(0xFF5EC8FF);
  static const iceDeep = Color(0xFF2E7BEA);
  static const logoGreen = Color(0xFF39F56B);
  static const logoLime = Color(0xFFB7FF39);
  static const logoTeal = Color(0xFF00C98B);
  static const lavender = Color(0xFFA8A9C7);
  // daily streak flame (same in both themes)
  static const flameCore = Color(0xFFFFF3B0);
  static const flameYellow = Color(0xFFFFD43B);
  static const flameOrange = Color(0xFFFF8A00);
  static const flameRed = Color(0xFFFF3D2E);
  static const flameMagenta = Color(0xFFFF2E93);
  static const gold = Color(0xFFFFC83D);
  static const ash = Color(0xFF6B6E8F);
}

ThemeData _base(ColorScheme cs) {
  final radius = BorderRadius.circular(14);
  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    scaffoldBackgroundColor: cs.surface,
    visualDensity: VisualDensity.standard,
    appBarTheme: AppBarTheme(
      backgroundColor: cs.surface,
      foregroundColor: cs.onSurface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: cs.onSurface, letterSpacing: -0.5),
    ),
    cardTheme: CardThemeData(
      color: cs.surfaceContainer,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: cs.surfaceContainerHigh,
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: cs.primary, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: radius),
        side: BorderSide(color: cs.outlineVariant),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: cs.surfaceContainerLow,
      indicatorColor: cs.primary.withValues(alpha: 0.18),
      labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
      height: 68,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

final darkTheme = _base(
  const ColorScheme(
    brightness: Brightness.dark,
    primary: Brand.neon,
    onPrimary: Brand.night,
    secondary: Brand.nightRaised,
    onSecondary: Colors.white,
    tertiary: Brand.volt,
    onTertiary: Brand.night,
    error: Color(0xFFFF5C7A),
    onError: Brand.night,
    surface: Brand.night,
    onSurface: Colors.white,
    onSurfaceVariant: Color(0xFFA9ACCB),
    surfaceContainerLowest: Color(0xFF0B0B1C),
    surfaceContainerLow: Color(0xFF14152E),
    surfaceContainer: Brand.nightCard,
    surfaceContainerHigh: Color(0xFF22254A),
    surfaceContainerHighest: Brand.nightRaised,
    outline: Color(0xFF4A4E7E),
    outlineVariant: Color(0xFF2F3262),
  ),
);

final lightTheme = _base(
  const ColorScheme(
    brightness: Brightness.light,
    primary: Brand.emerald,
    onPrimary: Colors.white,
    secondary: Brand.mist,
    onSecondary: Brand.ink,
    tertiary: Brand.amber,
    onTertiary: Colors.white,
    error: Color(0xFFC62848),
    onError: Colors.white,
    surface: Brand.paper,
    onSurface: Brand.ink,
    onSurfaceVariant: Color(0xFF5A5D7A),
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Colors.white,
    surfaceContainer: Colors.white,
    surfaceContainerHigh: Brand.mist,
    surfaceContainerHighest: Color(0xFFDCDFEE),
    outline: Color(0xFFB4B8D0),
    outlineVariant: Color(0xFFDCDFEE),
  ),
);

/// Dark by default; remembered on the device (like the web's localStorage toggle).
final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

class ThemeModeController extends Notifier<ThemeMode> {
  static const _key = 'theme_mode';

  @override
  ThemeMode build() {
    SharedPreferences.getInstance().then((p) {
      final v = p.getString(_key);
      if (v != null) state = ThemeMode.values.byName(v);
    });
    return ThemeMode.dark;
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    (await SharedPreferences.getInstance()).setString(_key, mode.name);
  }
}
