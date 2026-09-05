import 'package:flutter/material.dart';

/// The palette from the agreed design: deep blue-black with one warm accent.
///
/// A remote is used in a dark room, so the app commits to a single dark look
/// rather than following the system theme. Warm amber was chosen over the usual
/// cool accent because it sits comfortably in that room, and because spending
/// the only bright colour on one control — OK — makes it findable in the dark.
abstract final class Palette {
  static const ground = Color(0xFF0B0E14);
  static const groundLift = Color(0xFF10141C);
  static const surface = Color(0xFF171C26);
  static const surfaceHigh = Color(0xFF1E2531);

  static const ink = Color(0xFFECE9E3);
  static const inkMid = Color(0xFF9AA1AE);
  static const inkDim = Color(0xFF646C7A);

  static const amber = Color(0xFFE9A93F);
  static const amberDeep = Color(0xFFC4832A);
  static const amberWash = Color(0x22E9A93F);

  static const live = Color(0xFF57C98A);
  static const dead = Color(0xFFDE5B57);
}

abstract final class Radii {
  static const sm = 14.0;
  static const md = 20.0;
  static const lg = 28.0;
}

/// Light from above: a bright hairline on the top edge, a dark one below.
/// This is what gives a control the feel of a physical rubber button, and it is
/// also what separates areas without drawing a single border.
List<BoxShadow> get raisedShadow => const [
  BoxShadow(color: Color(0x6B000000), blurRadius: 20, offset: Offset(0, 8)),
];

const raisedGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Palette.surfaceHigh, Palette.surface],
);

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: Palette.amber,
    onPrimary: Color(0xFF2A1D08),
    surface: Palette.surface,
    onSurface: Palette.ink,
    error: Palette.dead,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.ground,
    // Messages carry real explanations, so they need to be as readable as the
    // rest of the app rather than a bright slab dropped on a dark screen.
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Palette.surfaceHigh,
      contentTextStyle: const TextStyle(color: Palette.ink, height: 1.45),
      actionTextColor: Palette.amber,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 8,
    ),
    fontFamily: 'Rubik',
    splashFactory: NoSplash.splashFactory,
    textTheme: const TextTheme(
      titleMedium: TextStyle(fontWeight: FontWeight.w600, color: Palette.ink),
      bodyMedium: TextStyle(color: Palette.ink, height: 1.5),
      bodySmall: TextStyle(color: Palette.inkDim, fontSize: 11.5),
      labelSmall: TextStyle(color: Palette.inkDim, fontSize: 10.5),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.05),
      hintStyle: const TextStyle(color: Palette.inkDim),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
  );
}
