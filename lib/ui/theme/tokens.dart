import 'package:flutter/material.dart';

abstract final class Zc {
  static const background = Color(0xFF0B0B12);
  static const surface = Color(0xFF16161F);
  static const surfaceHigh = Color(0xFF1E1E2A);
  static const surfaceTop = Color(0xFF2A2A38);
  static const outline = Color(0x22FFFFFF);

  static const text = Color(0xFFFFFFFF);
  static const textMuted = Color(0xB3FFFFFF);
  static const textFaint = Color(0x73FFFFFF);

  static const accent = Color(0xFF6C63FF);
  static const accentSoft = Color(0xFF8E87FF);

  static const request = Color(0xFFF5B544);

  static const cinema = Color(0xFFFF8F6B);

  static const success = Color(0xFF3DDC97);
  static const danger = Color(0xFFFF5D6C);
  static const rating = Color(0xFFFFC94D);
}

abstract final class Zs {
  static const pageInset = 72.0;
  static const railCollapsed = 104.0;
  static const railExpanded = 300.0;
  static const rowGap = 44.0;
  static const cardGap = 22.0;
  static const radius = 14.0;
  static const radiusLarge = 22.0;

  static const posterWidth = 200.0;
  static const landscapeWidth = 380.0;
}

abstract final class Zm {
  static const fast = Duration(milliseconds: 140);
  static const normal = Duration(milliseconds: 220);
  static const slow = Duration(milliseconds: 420);
  static const backdropDebounce = Duration(milliseconds: 260);
  static const curve = Curves.easeOutCubic;
}

abstract final class Zt {
  static const _base = TextStyle(color: Zc.text, height: 1.2, letterSpacing: 0.1);

  static final display = _base.copyWith(fontSize: 64, fontWeight: FontWeight.w700, height: 1.05, letterSpacing: -0.5);
  static final headline = _base.copyWith(fontSize: 40, fontWeight: FontWeight.w700, letterSpacing: -0.2);
  static final title = _base.copyWith(fontSize: 30, fontWeight: FontWeight.w600);
  static final rowTitle = _base.copyWith(fontSize: 26, fontWeight: FontWeight.w600, color: Zc.textMuted);
  static final body = _base.copyWith(fontSize: 22, height: 1.45, color: Zc.textMuted);
  static final label = _base.copyWith(fontSize: 20, fontWeight: FontWeight.w600);
  static final caption = _base.copyWith(fontSize: 18, color: Zc.textFaint);
  static final meta = _base.copyWith(fontSize: 21, fontWeight: FontWeight.w500, color: Zc.textMuted);
}

ThemeData buildTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: Zc.background,
    canvasColor: Zc.background,
    colorScheme: const ColorScheme.dark(
      primary: Zc.accent,
      secondary: Zc.request,
      surface: Zc.surface,
      error: Zc.danger,
    ),
    focusColor: Colors.transparent,
    hoverColor: Colors.transparent,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    textSelectionTheme: const TextSelectionThemeData(cursorColor: Zc.accent),
  );
}
