import 'package:flutter/material.dart';

import '../core/store.dart';

// Brand colors sampled from assets/AppIcon.png and the logos.
const pawPink = Color(0xFFCB87AB);
const pawPinkLight = Color(0xFFE8B6D1);
const pawMauve = Color(0xFF8F6B7E);
const pawPlum = Color(0xFF401C30);
const pawIconBackground = Color(0xFF4A3340);
const pawOutline = Color(0xFF200810);

/// The pink wordmark, made for dark backgrounds.
const logoAsset = 'assets/LogoFlatBlack.png';
const iconAsset = 'assets/AppIcon.png';

ThemeChoice _choice = ThemeChoice.plum;

/// Switches the colors [canvas], [panel] and [ink] return. Widgets read them
/// directly, so the app rebuilds its whole tree after calling this.
void setPalette(ThemeChoice choice) => _choice = choice;

/// Page background.
Color get canvas => switch (_choice) {
  ThemeChoice.plum => const Color(0xFF22141B),
  ThemeChoice.amoled => Colors.black,
};

/// Raised surfaces: sheets, dialogs, chips and the drawer header.
Color get panel => switch (_choice) {
  ThemeChoice.plum => const Color(0xFF33212B),
  ThemeChoice.amoled => const Color(0xFF150C11),
};

/// Hairlines between posts, like X's separators.
Color get hairline => pawMauve.withValues(alpha: .28);

/// Text and icons at [opacity]: a pink-tinted white.
Color ink(double opacity) => const Color(0xFFFBEFF5).withValues(alpha: opacity);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: pawPink,
    brightness: Brightness.dark,
    primary: pawPink,
    onPrimary: pawOutline,
    secondary: pawPinkLight,
    surface: canvas,
    onSurface: ink(.94),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: canvas,
    canvasColor: canvas,
    appBarTheme: AppBarTheme(
      backgroundColor: canvas,
      surfaceTintColor: Colors.transparent,
      foregroundColor: ink(.94),
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: canvas,
      surfaceTintColor: Colors.transparent,
      width: 300,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: ink(.94),
      unselectedLabelColor: ink(.5),
      indicatorColor: pawPink,
      dividerColor: hairline,
      labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      unselectedLabelStyle: const TextStyle(
        fontWeight: FontWeight.w500,
        fontSize: 15,
      ),
      indicatorSize: TabBarIndicatorSize.label,
      indicator: const UnderlineTabIndicator(
        borderSide: BorderSide(color: pawPink, width: 4),
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
    ),
    dividerTheme: DividerThemeData(color: hairline, thickness: .6, space: .6),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: panel,
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: panel,
      surfaceTintColor: Colors.transparent,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: panel,
      selectedColor: pawPink.withValues(alpha: .28),
      side: BorderSide(color: pawPink.withValues(alpha: .2)),
      labelStyle: TextStyle(color: ink(.9)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: panel,
      hintStyle: TextStyle(color: ink(.45)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: pawPink,
        foregroundColor: pawOutline,
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: pawPinkLight,
      contentTextStyle: const TextStyle(color: pawOutline),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: pawPink),
    listTileTheme: ListTileThemeData(iconColor: ink(.85)),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? pawOutline : null,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? pawPink : null,
      ),
    ),
  );
}

/// The paw app icon in a rounded square.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * .28),
    child: Image.asset(iconAsset, width: size, height: size, fit: BoxFit.cover),
  );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: pawPink,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.8,
      ),
    ),
  );
}
