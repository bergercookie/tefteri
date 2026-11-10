/// The progress of the committed plan on the Week page.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/planning_models.dart';
import '../../theme/theme.dart';
import 'week_progress.dart';
import 'weekly_api.dart';
import 'weekly_widgets.dart';

/// What the user committed to for [week], and how far they have come.
///
/// Shows done and left counts, tasks completed on each day, the cadence and a
/// burndown chart. Shows nothing until the week has a committed plan, and
/// nothing when the plan cannot be loaded: the page works without it.
class WeekProgressCard extends ConsumerWidget {
  /// Creates the card for the week that starts on [week] (a Monday).
  ///
  /// [today] is for tests; it defaults to now.
  const WeekProgressCard({required this.week, this.today, super.key});

  /// Monday of the week the page shows.
  final DateTime week;

  /// The current day.
  final DateTime? today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan =
        ref.watch(weeklyStateProvider(dateKey(week))).valueOrNull?.plan;
    if (plan == null || !plan.committed) return const SizedBox.shrink();
    final progress = WeekProgress.of(plan, week, today ?? DateTime.now());
    final colors = context.tefteri;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('week-progress'),
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        border: Border.all(color: colors.rule),
        borderRadius: BorderRadius.circular(Corner.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text('Committed plan', style: text.titleMedium)),
              Text(
                '${progress.done} of ${plural(progress.committed, 'task')} done',
                key: const Key('progress-summary'),
                style: text.bodyMedium,
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(
            '${plural(plan.projects.length, 'project')}: '
            '${plan.projects.map((p) => p.name).join(', ')}',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: Space.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(Corner.pill),
            child: LinearProgressIndicator(
              key: const Key('progress-bar'),
              value: progress.fraction,
              minHeight: 8,
              color: colors.done,
              backgroundColor: colors.rule,
            ),
          ),
          const SizedBox(height: Space.lg),
          _Stats(progress: progress),
          const SizedBox(height: Space.lg),
          _DoneByDay(progress: progress, today: today ?? DateTime.now()),
          const SizedBox(height: Space.lg),
          Text('Burndown', style: text.titleMedium),
          const SizedBox(height: Space.sm),
          _Burndown(progress: progress),
          if (progress.doneBefore + progress.doneUndated > 0) ...[
            const SizedBox(height: Space.sm),
            Text(
              '${plural(progress.doneBefore + progress.doneUndated, 'task')} '
              'already done before the week or without a known day '
              'are not counted in the chart.',
              key: const Key('progress-undated'),
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

String _perDay(double v) => '${v.toStringAsFixed(1)} a day';

class _Stats extends StatelessWidget {
  const _Stats({required this.progress});

  final WeekProgress progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.tefteri;
    final cadence = progress.cadence;
    final need = progress.neededPerDay;
    final String verdict;
    if (progress.committed == 0) {
      verdict = 'Nothing was committed.';
    } else if (progress.left == 0) {
      verdict = 'Everything is done.';
    } else if (progress.daysLeft == 0) {
      verdict = 'The week is over.';
    } else if (cadence == null) {
      verdict = 'The week has not begun.';
    } else {
      verdict = progress.onTrack ? 'On track.' : 'Behind the plan.';
    }
    return Wrap(
      spacing: Space.xl,
      runSpacing: Space.md,
      children: [
        _Stat(
            key: const Key('stat-done'),
            label: 'Done',
            value: '${progress.done}',
            color: colors.done),
        _Stat(
            key: const Key('stat-left'),
            label: 'Left',
            value: '${progress.left}',
            color: colors.task),
        _Stat(
            key: const Key('stat-cadence'),
            label: 'Cadence',
            value: cadence == null ? '-' : _perDay(cadence)),
        _Stat(
            key: const Key('stat-needed'),
            label: 'Needed',
            value: need == null ? '-' : _perDay(need)),
        _Stat(key: const Key('stat-verdict'), label: 'Status', value: verdict),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    this.color,
    super.key,
  });

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
        Text(value, style: text.titleMedium?.copyWith(color: color)),
      ],
    );
  }
}

/// Tasks completed on each day, with the total.
class _DoneByDay extends StatelessWidget {
  const _DoneByDay({required this.progress, required this.today});

  final WeekProgress progress;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final colors = context.tefteri;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime(today.year, today.month, today.day);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
                child: Text('Completed per day',
                    style: text.labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant))),
            Text('Total ${progress.doneInWeek}',
                key: const Key('done-total'), style: text.labelSmall),
          ],
        ),
        const SizedBox(height: Space.xs),
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Builder(builder: (context) {
                  final day = DateTime(progress.monday.year,
                      progress.monday.month, progress.monday.day + i);
                  final isToday = day == now;
                  final n = progress.doneByDay[i];
                  return Container(
                    key: Key('done-day-$i'),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(vertical: Space.sm),
                    decoration: BoxDecoration(
                      color: isToday
                          ? colors.today
                          : i >= 5
                              ? colors.weekend
                              : null,
                      border:
                          Border.all(color: isToday ? colors.now : colors.rule),
                      borderRadius: BorderRadius.circular(Corner.sm),
                    ),
                    child: Column(
                      children: [
                        Text(weekdayShort(i),
                            style: text.labelSmall
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                        Text('$n',
                            style: text.titleMedium?.copyWith(
                                color: n > 0 ? colors.done : scheme.outline)),
                      ],
                    ),
                  );
                }),
              ),
          ],
        ),
      ],
    );
  }
}

/// Open tasks against the days of the week, with the ideal line.
class _Burndown extends StatelessWidget {
  const _Burndown({required this.progress});

  final WeekProgress progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.tefteri;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final label = text.labelSmall?.copyWith(color: scheme.onSurfaceVariant);
    final actual = progress.remainingByDay;
    final lastIndex = actual.lastIndexWhere((v) => v != null);
    final summary = lastIndex < 0
        ? 'Burndown: the week has not begun.'
        : 'Burndown: ${actual[lastIndex]} of ${progress.scope} tasks open '
            'after ${weekdayShort(lastIndex)}.';
    return Semantics(
      label: summary,
      container: true,
      child: ExcludeSemantics(
        child: Column(
          children: [
            SizedBox(
              height: 168,
              child: CustomPaint(
                key: const Key('burndown'),
                size: Size.infinite,
                painter: _BurndownPainter(
                  scope: progress.scope,
                  ideal: progress.idealByDay,
                  actual: actual,
                  actualColor: colors.task,
                  idealColor: scheme.outline,
                  gridColor: colors.rule,
                  labelStyle: label ?? const TextStyle(),
                  days: [for (var i = 0; i < 7; i++) weekdayShort(i)],
                ),
              ),
            ),
            const SizedBox(height: Space.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Key(color: colors.task, label: 'Open tasks', style: label),
                const SizedBox(width: Space.lg),
                _Key(
                    color: scheme.outline,
                    label: 'Ideal pace',
                    dashed: true,
                    style: label),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    required this.color,
    required this.label,
    required this.style,
    this.dashed = false,
  });

  final Color color;
  final String label;
  final TextStyle? style;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 20,
          height: 2,
          child: dashed
              ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (var i = 0; i < 3; i++) ...[
                    Expanded(child: ColoredBox(color: color)),
                    if (i < 2) const SizedBox(width: 3),
                  ]
                ])
              : ColoredBox(color: color),
        ),
        const SizedBox(width: Space.xs),
        Text(label, style: style),
      ],
    );
  }
}

class _BurndownPainter extends CustomPainter {
  _BurndownPainter({
    required this.scope,
    required this.ideal,
    required this.actual,
    required this.actualColor,
    required this.idealColor,
    required this.gridColor,
    required this.labelStyle,
    required this.days,
  });

  final int scope;
  final List<double> ideal;
  final List<int?> actual;
  final Color actualColor;
  final Color idealColor;
  final Color gridColor;
  final TextStyle labelStyle;
  final List<String> days;

  static const _left = 28.0;
  static const _bottom = 20.0;
  static const _top = 8.0;

  TextPainter _label(String s) => TextPainter(
        text: TextSpan(text: s, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width - _left - 8;
    final h = size.height - _top - _bottom;
    final top = scope < 1 ? 1 : scope;
    // x: 0 is Monday morning, 7 is Sunday night; a day's value sits at its end.
    double x(num d) => _left + w * d / 7;
    double y(num v) => _top + h * (1 - v / top);

    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    // Horizontal guides at 0 and at the top, plus the middle when it is a
    // whole number of tasks.
    for (final v in {0, top, if (top.isEven && top > 2) top ~/ 2}) {
      canvas.drawLine(Offset(_left, y(v)), Offset(size.width - 8, y(v)), grid);
      final t = _label('$v');
      t.paint(canvas, Offset(_left - 6 - t.width, y(v) - t.height / 2));
    }
    for (var i = 0; i < 7; i++) {
      final t = _label(days[i]);
      t.paint(canvas, Offset(x(i + 0.5) - t.width / 2, size.height - t.height));
    }

    // The ideal line, dashed, from the full scope on Monday morning.
    final idealPoints = [
      Offset(x(0), y(top)),
      for (var i = 0; i < 7; i++) Offset(x(i + 1), y(ideal[i])),
    ];
    final dash = Paint()
      ..color = idealColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < idealPoints.length - 1; i++) {
      _dashed(canvas, idealPoints[i], idealPoints[i + 1], dash);
    }

    // The open tasks at the end of each day that has begun.
    final line = Paint()
      ..color = actualColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final pts = [
      Offset(x(0), y(top)),
      for (var i = 0; i < 7; i++)
        if (actual[i] != null) Offset(x(i + 1), y(actual[i]!)),
    ];
    if (pts.length > 1) {
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final p in pts.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, line);
    }
    final dot = Paint()..color = actualColor;
    for (final p in pts.skip(1)) {
      canvas.drawCircle(p, 3.5, dot);
    }
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint paint) {
    final total = (b - a).distance;
    const on = 5.0, off = 4.0;
    final dir = (b - a) / total;
    for (var d = 0.0; d < total; d += on + off) {
      final end = d + on > total ? total : d + on;
      canvas.drawLine(a + dir * d, a + dir * end, paint);
    }
  }

  @override
  bool shouldRepaint(_BurndownPainter old) =>
      old.scope != scope ||
      old.actual != actual ||
      old.ideal != ideal ||
      old.actualColor != actualColor ||
      old.idealColor != idealColor ||
      old.gridColor != gridColor ||
      old.labelStyle != labelStyle;
}
