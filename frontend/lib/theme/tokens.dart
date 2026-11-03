/// Spacing, shape and motion tokens shared by every screen.
library;

import 'package:flutter/material.dart';

/// Spacing scale in logical pixels.
abstract final class Space {
  /// 4 px.
  static const double xs = 4;

  /// 8 px.
  static const double sm = 8;

  /// 12 px.
  static const double md = 12;

  /// 16 px.
  static const double lg = 16;

  /// 24 px.
  static const double xl = 24;

  /// 32 px.
  static const double xxl = 32;
}

/// Corner radii. The look is crisp: small radii, pill shapes only for
/// switches and chips.
abstract final class Corner {
  /// Event blocks and small surfaces.
  static const double sm = 4;

  /// Buttons, inputs and rows.
  static const double md = 6;

  /// Cards and dialogs.
  static const double lg = 10;

  /// Chips and the context switch.
  static const double pill = 999;
}

/// Motion lengths. Respect [MediaQuery.disableAnimationsOf] when using them.
abstract final class Motion {
  /// Hover and small state changes.
  static const Duration quick = Duration(milliseconds: 150);

  /// Page changes and larger movements.
  static const Duration page = Duration(milliseconds: 240);

  /// The curve for entrances.
  static const Curve enter = Curves.easeOutCubic;

  /// [d], or zero when the user asked for reduced motion.
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : d;
}

/// Font family names bundled in `assets/fonts`.
abstract final class Fonts {
  /// Display face for titles and headings (Instrument Serif).
  static const String display = 'InstrumentSerif';

  /// Face for everything else (IBM Plex Sans).
  static const String ui = 'IBMPlexSans';
}
