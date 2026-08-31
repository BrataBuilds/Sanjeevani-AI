import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'motion.dart';

/// The Sanjeevani design system: colour tokens, spacing/radius scale and
/// typography, lifted from the "Sanjeevani Patient App" design canvas.
/// Two ink-on-surface palettes (light/dark), one accent (teal), one danger
/// (red, used only for the emergency/red-flag path) and one mid tone (amber,
/// used for the middle of the urgency scale).
@immutable
class SanjeevaniColors extends ThemeExtension<SanjeevaniColors> {
  const SanjeevaniColors({
    required this.canvas,
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.line,
    required this.acc,
    required this.accSoft,
    required this.accInk,
    required this.dan,
    required this.danSoft,
    required this.mid,
    required this.stub,
  });

  final Color canvas;
  final Color bg;
  final Color surface;
  final Color surface2;
  final Color ink;
  final Color ink2;
  final Color ink3;
  final Color line;
  final Color acc;
  final Color accSoft;
  final Color accInk;
  final Color dan;
  final Color danSoft;
  final Color mid;
  final Color stub;

  static const light = SanjeevaniColors(
    canvas: Color(0xFFE9ECEC),
    bg: Color(0xFFF4F6F6),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFECEFF0),
    ink: Color(0xFF13181A),
    ink2: Color(0xFF576063),
    ink3: Color(0xFF899093),
    line: Color(0xFFDDE2E3),
    acc: Color(0xFF357574),
    accSoft: Color(0xFFDFF3F3),
    accInk: Color(0xFFFFFFFF),
    dan: Color(0xFFB63132),
    danSoft: Color(0xFFFEE8E6),
    mid: Color(0xFFA06F30),
    stub: Color(0xFF8F9699),
  );

  static const dark = SanjeevaniColors(
    canvas: Color(0xFF0A0D0D),
    bg: Color(0xFF121617),
    surface: Color(0xFF181D1E),
    surface2: Color(0xFF212829),
    ink: Color(0xFFEEF2F2),
    ink2: Color(0xFFA8B2B4),
    ink3: Color(0xFF7C8688),
    line: Color(0xFF2B3334),
    acc: Color(0xFF68B4B3),
    accSoft: Color(0xFF0A3535),
    accInk: Color(0xFF0A0D0D),
    dan: Color(0xFFED756E),
    danSoft: Color(0xFF4B1D1B),
    mid: Color(0xFFE1AC6E),
    stub: Color(0xFF6C7679),
  );

  @override
  SanjeevaniColors copyWith({
    Color? canvas,
    Color? bg,
    Color? surface,
    Color? surface2,
    Color? ink,
    Color? ink2,
    Color? ink3,
    Color? line,
    Color? acc,
    Color? accSoft,
    Color? accInk,
    Color? dan,
    Color? danSoft,
    Color? mid,
    Color? stub,
  }) {
    return SanjeevaniColors(
      canvas: canvas ?? this.canvas,
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      ink: ink ?? this.ink,
      ink2: ink2 ?? this.ink2,
      ink3: ink3 ?? this.ink3,
      line: line ?? this.line,
      acc: acc ?? this.acc,
      accSoft: accSoft ?? this.accSoft,
      accInk: accInk ?? this.accInk,
      dan: dan ?? this.dan,
      danSoft: danSoft ?? this.danSoft,
      mid: mid ?? this.mid,
      stub: stub ?? this.stub,
    );
  }

  @override
  SanjeevaniColors lerp(ThemeExtension<SanjeevaniColors>? other, double t) {
    if (other is! SanjeevaniColors) return this;
    return SanjeevaniColors(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      ink2: Color.lerp(ink2, other.ink2, t)!,
      ink3: Color.lerp(ink3, other.ink3, t)!,
      line: Color.lerp(line, other.line, t)!,
      acc: Color.lerp(acc, other.acc, t)!,
      accSoft: Color.lerp(accSoft, other.accSoft, t)!,
      accInk: Color.lerp(accInk, other.accInk, t)!,
      dan: Color.lerp(dan, other.dan, t)!,
      danSoft: Color.lerp(danSoft, other.danSoft, t)!,
      mid: Color.lerp(mid, other.mid, t)!,
      stub: Color.lerp(stub, other.stub, t)!,
    );
  }
}

/// Spacing scale from the canvas: 4 · 8 · 12 · 16 · 20 · 26.
class SanjeevaniSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 26;
}

/// Corner radii from the canvas: 12 / 16 / 20 / 24.
class SanjeevaniRadius {
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
}

/// Numbered 1 (most urgent) to 5 (least), matching the canvas's urgency
/// legend: colour, notch height and word all carry the level so it never
/// depends on colour alone.
class UrgencyLevel {
  static Color colorOf(SanjeevaniColors c, int level) {
    if (level <= 2) return c.dan;
    if (level == 3) return c.mid;
    return c.ink2;
  }

  static String labelOf(int level) => switch (level) {
        1 => 'Immediate',
        2 => 'Very urgent',
        3 => 'Urgent',
        4 => 'Standard',
        _ => 'Non-urgent',
      };
}

ThemeData _buildTheme(SanjeevaniColors c, Brightness brightness) {
  final base = brightness == Brightness.dark ? ThemeData.dark() : ThemeData.light();
  final textTheme = GoogleFonts.figtreeTextTheme(base.textTheme).copyWith(
    displaySmall: GoogleFonts.fraunces(fontSize: 38, height: 1.05, color: c.ink),
    headlineMedium: GoogleFonts.fraunces(fontSize: 30, height: 1.15, color: c.ink),
    headlineSmall: GoogleFonts.fraunces(fontSize: 26, height: 1.15, color: c.ink),
    titleLarge: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: c.ink),
    titleMedium: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.ink),
    titleSmall: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.ink),
    bodyLarge: TextStyle(fontSize: 17, color: c.ink),
    bodyMedium: TextStyle(fontSize: 16, color: c.ink),
    bodySmall: TextStyle(fontSize: 14, color: c.ink2),
    labelSmall: TextStyle(
      fontSize: 11,
      letterSpacing: 1.4,
      fontWeight: FontWeight.w500,
      color: c.ink3,
    ),
  ).apply(
    fontFamilyFallback: [
      GoogleFonts.notoSansOriya().fontFamily!,
      GoogleFonts.notoSansDevanagari().fontFamily!,
    ],
  );

  final colorScheme = (brightness == Brightness.dark
          ? const ColorScheme.dark()
          : const ColorScheme.light())
      .copyWith(
    brightness: brightness,
    primary: c.acc,
    onPrimary: c.accInk,
    primaryContainer: c.accSoft,
    onPrimaryContainer: c.acc,
    secondary: c.mid,
    onSecondary: c.accInk,
    error: c.dan,
    onError: c.accInk,
    errorContainer: c.danSoft,
    onErrorContainer: c.dan,
    surface: c.surface,
    onSurface: c.ink,
    surfaceContainerHighest: c.surface2,
    onSurfaceVariant: c.ink2,
    outline: c.line,
    outlineVariant: c.line,
  );

  return base.copyWith(
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: c.bg,
    textTheme: textTheme,
    extensions: [c],
    pageTransitionsTheme: SanjeevaniMotion.pageTransitions,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      labelStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.ink2),
      contentPadding: const EdgeInsets.all(16),
      constraints: const BoxConstraints(minHeight: 56),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SanjeevaniRadius.md),
        borderSide: BorderSide(color: c.line, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SanjeevaniRadius.md),
        borderSide: BorderSide(color: c.line, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SanjeevaniRadius.md),
        borderSide: BorderSide(color: c.acc, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SanjeevaniRadius.md),
        borderSide: BorderSide(color: c.dan, width: 1.5),
      ),
    ),
    // Size.fromHeight(h) means Size(double.infinity, h) — an infinite *minimum*
    // width, which is how these buttons fill their column. It only works where
    // width is bounded. Inside a Row, Wrap, or any unbounded parent it throws
    // "BoxConstraints forces an infinite width" and takes down the whole
    // subtree, so wrap the button in an Expanded or Flexible there.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.acc,
        foregroundColor: c.accInk,
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SanjeevaniRadius.md)),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.ink,
        minimumSize: const Size.fromHeight(52),
        side: BorderSide(color: c.line, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SanjeevaniRadius.md)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: c.acc),
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SanjeevaniRadius.lg),
        side: BorderSide(color: c.line),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: c.surface2,
      side: BorderSide(color: c.line),
      labelStyle: TextStyle(fontSize: 14, color: c.ink),
    ),
    dividerTheme: DividerThemeData(color: c.line, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: c.bg,
      foregroundColor: c.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface,
      indicatorColor: c.accSoft,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? c.acc : c.ink3,
          )),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? c.acc : c.ink3,
          )),
    ),
  );
}

final ThemeData sanjeevaniLightTheme = _buildTheme(SanjeevaniColors.light, Brightness.light);
final ThemeData sanjeevaniDarkTheme = _buildTheme(SanjeevaniColors.dark, Brightness.dark);

extension SanjeevaniThemeContext on BuildContext {
  SanjeevaniColors get sc => Theme.of(this).extension<SanjeevaniColors>()!;
}
