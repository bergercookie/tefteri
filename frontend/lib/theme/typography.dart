/// Type scale: a serif display face for headings, a humanist sans for the UI.
library;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// Tabular figures keep times and counts from jittering.
const _tabular = [FontFeature.tabularFigures()];

/// The text theme for [scheme]'s colors.
///
/// Instrument Serif has a single weight, so every serif style is pinned to
/// w400; asking for bold would make the engine fake it.
TextTheme tefteriTextTheme(ColorScheme scheme) {
  TextStyle serif(double size, {double height = 1.15, double spacing = -0.2}) =>
      TextStyle(
        fontFamily: Fonts.display,
        fontSize: size,
        height: height,
        letterSpacing: spacing,
        fontWeight: FontWeight.w400,
        color: scheme.onSurface,
      );
  TextStyle sans(double size, FontWeight w,
          {double height = 1.4, double spacing = 0, Color? color}) =>
      TextStyle(
        fontFamily: Fonts.ui,
        fontSize: size,
        height: height,
        letterSpacing: spacing,
        fontWeight: w,
        color: color ?? scheme.onSurface,
        fontFeatures: _tabular,
      );
  return TextTheme(
    displayLarge: serif(56),
    displayMedium: serif(44),
    displaySmall: serif(36),
    headlineLarge: serif(32),
    headlineMedium: serif(28),
    headlineSmall: serif(24),
    titleLarge: serif(22, spacing: 0),
    // Section headings ("Events", "Tasks") are set in the serif face.
    titleMedium: serif(20, spacing: 0),
    titleSmall: sans(14, FontWeight.w500, height: 1.35),
    bodyLarge: sans(16, FontWeight.w400, height: 1.5),
    bodyMedium: sans(14, FontWeight.w400, height: 1.45),
    bodySmall:
        sans(12, FontWeight.w400, height: 1.4, color: scheme.onSurfaceVariant),
    labelLarge: sans(14, FontWeight.w500, spacing: 0.1),
    labelMedium: sans(12, FontWeight.w500, spacing: 0.2),
    labelSmall: sans(11, FontWeight.w500, spacing: 0.3),
  );
}
