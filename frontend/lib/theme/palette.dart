/// The Tefteri palette: warm paper and ink, in light and dark.
library;

import 'package:flutter/material.dart';

/// Colors that Material's [ColorScheme] has no role for.
///
/// Read them with `context.tefteri`. Without a Tefteri theme (a bare
/// `MaterialApp` in a test) the light values are used.
@immutable
class TefteriColors extends ThemeExtension<TefteriColors> {
  /// Creates a palette.
  const TefteriColors({
    required this.paper,
    required this.rule,
    required this.margin,
    required this.now,
    required this.event,
    required this.eventContainer,
    required this.task,
    required this.taskContainer,
    required this.done,
    required this.weekend,
    required this.today,
  });

  /// Page background, the color of the notebook paper.
  final Color paper;

  /// Hairlines: ruled lines and dividers.
  final Color rule;

  /// The red margin line of a notebook page.
  final Color margin;

  /// The "now" marker on the calendar.
  final Color now;

  /// Accent of calendar events.
  final Color event;

  /// Tint of calendar event blocks.
  final Color eventContainer;

  /// Accent of tasks.
  final Color task;

  /// Tint of task blocks.
  final Color taskContainer;

  /// Finished work.
  final Color done;

  /// Tint of weekend columns.
  final Color weekend;

  /// Tint of today's column.
  final Color today;

  /// The light palette.
  static const light = TefteriColors(
    paper: Color(0xFFF6F1E7),
    rule: Color(0xFFE2D9C6),
    margin: Color(0xFFE5A99C),
    now: Color(0xFFD64933),
    event: Color(0xFF2F4B7C),
    eventContainer: Color(0xFFDCE4F2),
    task: Color(0xFFB5532F),
    taskContainer: Color(0xFFF6DFD2),
    done: Color(0xFF5B7553),
    weekend: Color(0x0F8A7B5A),
    today: Color(0x1F5B86C9),
  );

  /// The dark palette ("midnight ink").
  static const dark = TefteriColors(
    paper: Color(0xFF14171F),
    rule: Color(0xFF2C3242),
    margin: Color(0xFF6B3F3A),
    now: Color(0xFFFF7A62),
    event: Color(0xFF9DB6E8),
    eventContainer: Color(0xFF26365A),
    task: Color(0xFFE39A78),
    taskContainer: Color(0xFF4A2E22),
    done: Color(0xFF9DBA94),
    weekend: Color(0x0FFFFFFF),
    today: Color(0x229DB6E8),
  );

  @override
  TefteriColors copyWith({
    Color? paper,
    Color? rule,
    Color? margin,
    Color? now,
    Color? event,
    Color? eventContainer,
    Color? task,
    Color? taskContainer,
    Color? done,
    Color? weekend,
    Color? today,
  }) =>
      TefteriColors(
        paper: paper ?? this.paper,
        rule: rule ?? this.rule,
        margin: margin ?? this.margin,
        now: now ?? this.now,
        event: event ?? this.event,
        eventContainer: eventContainer ?? this.eventContainer,
        task: task ?? this.task,
        taskContainer: taskContainer ?? this.taskContainer,
        done: done ?? this.done,
        weekend: weekend ?? this.weekend,
        today: today ?? this.today,
      );

  @override
  TefteriColors lerp(TefteriColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return TefteriColors(
      paper: l(paper, other.paper),
      rule: l(rule, other.rule),
      margin: l(margin, other.margin),
      now: l(now, other.now),
      event: l(event, other.event),
      eventContainer: l(eventContainer, other.eventContainer),
      task: l(task, other.task),
      taskContainer: l(taskContainer, other.taskContainer),
      done: l(done, other.done),
      weekend: l(weekend, other.weekend),
      today: l(today, other.today),
    );
  }
}

/// Access to [TefteriColors] from a [BuildContext].
extension TefteriTheme on BuildContext {
  /// The palette of the current theme.
  TefteriColors get tefteri =>
      Theme.of(this).extension<TefteriColors>() ?? TefteriColors.light;
}

/// The Material color scheme, written by hand instead of grown from a seed.
ColorScheme tefteriScheme(Brightness brightness) {
  if (brightness == Brightness.dark) {
    return const ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFF9DB6E8),
      onPrimary: Color(0xFF14233F),
      primaryContainer: Color(0xFF26365A),
      onPrimaryContainer: Color(0xFFDCE4F7),
      secondary: Color(0xFFE39A78),
      onSecondary: Color(0xFF3A1F12),
      secondaryContainer: Color(0xFF4A2E22),
      onSecondaryContainer: Color(0xFFF6DFD2),
      tertiary: Color(0xFF9DBA94),
      onTertiary: Color(0xFF1B2E17),
      tertiaryContainer: Color(0xFF2E4129),
      onTertiaryContainer: Color(0xFFD9EACF),
      error: Color(0xFFFF8A7A),
      onError: Color(0xFF4A0E07),
      errorContainer: Color(0xFF5A2018),
      onErrorContainer: Color(0xFFFFDAD3),
      surface: Color(0xFF1B1F29),
      onSurface: Color(0xFFECE7DB),
      onSurfaceVariant: Color(0xFFA9A89F),
      surfaceContainerLowest: Color(0xFF14171F),
      surfaceContainerLow: Color(0xFF1B1F29),
      surfaceContainer: Color(0xFF212633),
      surfaceContainerHigh: Color(0xFF282E3D),
      surfaceContainerHighest: Color(0xFF30374A),
      outline: Color(0xFF58607A),
      outlineVariant: Color(0xFF2C3242),
      inverseSurface: Color(0xFFECE7DB),
      onInverseSurface: Color(0xFF1B1F29),
      inversePrimary: Color(0xFF2F4B7C),
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
    );
  }
  return const ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF2F4B7C),
    onPrimary: Color(0xFFFBF8F1),
    primaryContainer: Color(0xFFDCE4F2),
    onPrimaryContainer: Color(0xFF14233F),
    secondary: Color(0xFFB5532F),
    onSecondary: Color(0xFFFBF8F1),
    secondaryContainer: Color(0xFFF6DFD2),
    onSecondaryContainer: Color(0xFF4A2210),
    tertiary: Color(0xFF5B7553),
    onTertiary: Color(0xFFFBF8F1),
    tertiaryContainer: Color(0xFFDDE7D4),
    onTertiaryContainer: Color(0xFF1B2E17),
    error: Color(0xFFB23A2E),
    onError: Color(0xFFFBF8F1),
    errorContainer: Color(0xFFF8DAD4),
    onErrorContainer: Color(0xFF4A0E07),
    surface: Color(0xFFFBF8F1),
    onSurface: Color(0xFF1F2430),
    onSurfaceVariant: Color(0xFF5E6068),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF9F5EC),
    surfaceContainer: Color(0xFFF1EBDD),
    surfaceContainerHigh: Color(0xFFEBE4D3),
    surfaceContainerHighest: Color(0xFFE5DDCA),
    outline: Color(0xFF8E8A7C),
    outlineVariant: Color(0xFFE2D9C6),
    inverseSurface: Color(0xFF1F2430),
    onInverseSurface: Color(0xFFF6F1E7),
    inversePrimary: Color(0xFF9DB6E8),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
  );
}
