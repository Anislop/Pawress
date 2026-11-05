import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/store.dart';

// Brand colors sampled from assets/AppIcon.png and the logos.
const pawPink = Color(0xFFCB87AB);
const pawPinkLight = Color(0xFFE8B6D1);
const pawMauve = Color(0xFF8F6B7E);
const pawPlum = Color(0xFF401C30);
const pawIconBackground = Color(0xFF4A3340);
const pawOutline = Color(0xFF200810);

/// A deeper pink for text and accents on the light theme, where
/// [pawPinkLight] would wash out.
const pawPinkDeep = Color(0xFF9E4A76);

/// The wordmark for the current theme: pink on dark surfaces, plum on
/// light ones.
String get logoAsset =>
    isLight ? 'assets/LogoFlatWhite.png' : 'assets/LogoFlatBlack.png';
const iconAsset = 'assets/AppIcon.png';

ThemeChoice _choice = ThemeChoice.plum;

/// Switches the colors [canvas], [panel] and [ink] return. Widgets read them
/// directly, so the app rebuilds its whole tree after calling this.
/// [ThemeChoice.system] picks Light or Plum from [platform].
void setPalette(ThemeChoice choice, {Brightness platform = Brightness.dark}) =>
    _choice = choice == ThemeChoice.system
    ? (platform == Brightness.light ? ThemeChoice.light : ThemeChoice.plum)
    : choice;

bool get isLight => _choice == ThemeChoice.light;

/// Page background.
Color get canvas => switch (_choice) {
  ThemeChoice.amoled => Colors.black,
  ThemeChoice.light => const Color(0xFFFFF8FB),
  _ => const Color(0xFF22141B),
};

/// Raised surfaces: sheets, dialogs, chips and the drawer header.
Color get panel => switch (_choice) {
  ThemeChoice.amoled => const Color(0xFF150C11),
  ThemeChoice.light => const Color(0xFFF6E7EF),
  _ => const Color(0xFF33212B),
};

/// Hairlines between posts, like X's separators.
Color get hairline => pawMauve.withValues(alpha: isLight ? .22 : .28);

/// Text and icons at [opacity]: a pink-tinted white, or a deep plum on the
/// light theme.
Color ink(double opacity) =>
    (isLight ? const Color(0xFF2A1220) : const Color(0xFFFBEFF5)).withValues(
      alpha: opacity,
    );

/// Pink text and active icons that stay readable on [canvas].
Color get pinkText => isLight ? pawPinkDeep : pawPinkLight;

ThemeData buildTheme() {
  final brightness = isLight ? Brightness.light : Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: pawPink,
    brightness: brightness,
    primary: isLight ? pawPinkDeep : pawPink,
    onPrimary: isLight ? Colors.white : pawOutline,
    secondary: pinkText,
    surface: canvas,
    onSurface: ink(.94),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: canvas,
    canvasColor: canvas,
    appBarTheme: AppBarTheme(
      backgroundColor: canvas,
      surfaceTintColor: Colors.transparent,
      foregroundColor: ink(.94),
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: isLight
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
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
