/// The color that the user chose for a calendar in the calendar app.
library;

import 'package:flutter/material.dart';

import '../theme/theme.dart';

final _hex = RegExp(r'^#([0-9a-fA-F]{2})([0-9a-fA-F]{2})([0-9a-fA-F]{2})$');

/// Reads `#rrggbb`. Answers null for anything else, so that the app falls back
/// to its own colors.
Color? parseCalendarColor(String? hex) {
  final m = hex == null ? null : _hex.firstMatch(hex);
  if (m == null) return null;
  int part(int group) => int.parse(m.group(group)!, radix: 16);
  return Color.fromARGB(255, part(1), part(2), part(3));
}

/// A calendar color softened so that dark text reads on it (light theme) or
/// light text does (dark theme): the color over the paper of the page.
Color calendarTint(BuildContext context, Color calendar) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return Color.alphaBlend(
      calendar.withValues(alpha: dark ? 0.38 : 0.24), context.tefteri.paper);
}
