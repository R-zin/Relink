import 'package:flutter/material.dart';

/// Calm Humanitarian theme (master plan §2).
///
/// Warm, reassuring, plain-language — optimized for someone who may be
/// frightened, not for looking like a tactical ops console. The alarm red is
/// RESERVED for the SOS button and Severe/Red alert tags only, so it keeps
/// its urgency signal instead of becoming visual noise.
class RelinkColors {
  RelinkColors._();

  static const Color scaffold = Color(0xFFFAF8F5); // warm off-white
  static const Color text = Color(0xFF3A3632); // warm gray
  static const Color primary = Color(0xFF2E7E7B); // soft blue-teal
  static const Color alarmRed = Color(0xFFD64545); // RESERVED: SOS + severe alerts only
  static const Color pinShelter = Color(0xFF2E7E7B); // teal
  static const Color pinHazard = Color(0xFFE8A13A); // amber
  static const Color pinMissing = Color(0xFF8B6FC7); // violet
  // SOS pins reuse alarmRed (reserved color, correct context).
}

ThemeData buildRelinkTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: RelinkColors.primary,
      primary: RelinkColors.primary,
      surface: RelinkColors.scaffold,
    ),
  );
  return base.copyWith(
    scaffoldBackgroundColor: RelinkColors.scaffold,
    appBarTheme: const AppBarTheme(
      backgroundColor: RelinkColors.scaffold,
      foregroundColor: RelinkColors.text,
      elevation: 0,
      centerTitle: true,
    ),
    textTheme: base.textTheme
        .apply(
          bodyColor: RelinkColors.text,
          displayColor: RelinkColors.text,
        )
        .copyWith(
          bodyLarge: const TextStyle(
              fontSize: 16, height: 1.5, color: RelinkColors.text),
          bodyMedium: const TextStyle(
              fontSize: 15, height: 1.5, color: RelinkColors.text),
          titleLarge: const TextStyle(
              fontSize: 20, fontWeight: FontWeight.w600, color: RelinkColors.text),
          titleMedium: const TextStyle(
              fontSize: 17, fontWeight: FontWeight.w600, color: RelinkColors.text),
        ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: RelinkColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(64, 48),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
