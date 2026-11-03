import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/theme/theme.dart';

/// Screens must take their look from the theme, so one change in `lib/theme`
/// restyles the app and a later edit cannot drift back to Material defaults.
void main() {
  test('feature and core code has no hard-coded colors or fonts', () {
    final offenders = <String>[];
    final color = RegExp(r'Color\(0x|Colors\.(?!transparent\b)');
    final font = RegExp(r"fontFamily:\s*'|Roboto");
    for (final dir in ['lib/features', 'lib/core']) {
      for (final f in Directory(dir).listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (color.hasMatch(lines[i]) || font.hasMatch(lines[i])) {
            offenders.add('${f.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('the theme is not a seeded Material default', () {
    for (final b in Brightness.values) {
      final t = buildTefteriTheme(b);
      expect(t.textTheme.bodyMedium?.fontFamily, Fonts.ui);
      expect(t.textTheme.headlineSmall?.fontFamily, Fonts.display);
      expect(t.extension<TefteriColors>(), isNotNull);
      expect(t.colorScheme.brightness, b);
      expect(t.scaffoldBackgroundColor, t.extension<TefteriColors>()!.paper);
      expect(t.cardTheme.elevation, 0);
    }
  });

  test('light and dark differ', () {
    final light = buildTefteriTheme(Brightness.light);
    final dark = buildTefteriTheme(Brightness.dark);
    expect(light.scaffoldBackgroundColor, isNot(dark.scaffoldBackgroundColor));
    expect(light.colorScheme.primary, isNot(dark.colorScheme.primary));
  });

  test('text and surfaces keep a readable contrast', () {
    double contrast(Color a, Color b) {
      final la = a.computeLuminance() + 0.05;
      final lb = b.computeLuminance() + 0.05;
      return la > lb ? la / lb : lb / la;
    }

    for (final b in Brightness.values) {
      final s = tefteriScheme(b);
      final paper =
          (b == Brightness.dark ? TefteriColors.dark : TefteriColors.light)
              .paper;
      expect(contrast(s.onSurface, paper), greaterThan(7));
      expect(contrast(s.onSurfaceVariant, paper), greaterThan(4.5));
      expect(contrast(s.onPrimary, s.primary), greaterThan(4.5));
      expect(
          contrast(s.onPrimaryContainer, s.primaryContainer), greaterThan(7));
      expect(contrast(s.onSecondaryContainer, s.secondaryContainer),
          greaterThan(7));
    }
  });
}
