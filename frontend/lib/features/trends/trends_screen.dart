/// The Trends page: the weeks side by side, to see whether things improve.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/planning_models.dart' show dateKey;
import '../../core/shell.dart';
import '../../theme/theme.dart';
import '../statistics/category_style.dart';
import '../statistics/statistics_models.dart' show Category;
import 'trend_lines_card.dart';
import 'trends_api.dart';
import 'trends_models.dart';

/// The numbers of the weeks as charts and a table, and the latest finished week
/// against the weeks before it. Counts only: tefteri does not measure time.
class TrendsScreen extends ConsumerStatefulWidget {
  /// Creates the page.
  const TrendsScreen({super.key});

  @override
  ConsumerState<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends ConsumerState<TrendsScreen> {
  static const _choices = [8, 12, 26];
  int _weeks = 12;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(trendsProvider(_weeks));
    return AppShell(
      title: 'Trends',
      backTo: '/week',
      body: async.when(
        loading: () => const Loading(),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(apiErrorMessage(e), key: const Key('trends-error')),
              TextButton(
                key: const Key('trends-retry'),
                onPressed: () => ref.invalidate(trendsProvider(_weeks)),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
        data: _content,
      ),
    );
  }

  Widget _content(List<WeekMetrics> weeks) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final withData = weeks.where((w) => w.hasData).length;
    final latest = latestFinishedWeek(weeks);
    final comparison = latest == null ? null : compareWeek(weeks, latest);
    return ListView(
      padding: const EdgeInsets.all(Space.lg),
      children: [
        Wrap(
          spacing: Space.md,
          runSpacing: Space.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('How your weeks compare', style: text.titleLarge),
            SegmentedButton<int>(
              key: const Key('trends-range'),
              showSelectedIcon: false,
              segments: [
                for (final n in _choices)
                  ButtonSegment(value: n, label: Text('$n weeks')),
              ],
              selected: {_weeks},
              onSelectionChanged: (s) => setState(() => _weeks = s.first),
            ),
          ],
        ),
        const SizedBox(height: Space.xs),
        Text(
          'Numbers only: the tasks, milestones and themes that you completed. '
          'Tefteri does not measure time. The week that is running is shown '
          'so far and is not compared.',
          key: const Key('trends-note'),
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: Space.lg),
        if (withData == 0)
          const EmptyState(
            key: Key('trends-empty'),
            message: 'No week has numbers yet. Plan a week and complete some '
                'tasks, and the weeks show here.',
          )
        else ...[
          if (comparison != null) TrendLinesCard(comparison: comparison),
          const SizedBox(height: Space.lg),
          _Section(
            title: 'Tasks completed each week',
            child: _StackedBars(weeks: weeks),
          ),
          const SizedBox(height: Space.lg),
          _Section(
            title: 'How much of the committed plan was done',
            child: _CompletionBars(weeks: weeks),
          ),
          const SizedBox(height: Space.lg),
          _Section(
              title: 'All the numbers', child: _NumbersTable(weeks: weeks)),
        ],
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Space.sm),
          child,
        ],
      );
}

String _short(DateTime d) =>
    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// A bar for each week: the completed tasks, split into the three categories.
class _StackedBars extends StatelessWidget {
  const _StackedBars({required this.weeks});

  final List<WeekMetrics> weeks;

  static const double _height = 140;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = context.tefteri;
    final text = Theme.of(context).textTheme;
    final most =
        weeks.fold<int>(1, (m, w) => w.tasksDone > m ? w.tasksDone : m);
    Widget seg(int n, Color color) => n == 0
        ? const SizedBox.shrink()
        : Container(height: _height * n / most, color: color);
    final goal = categoryStyle(context, Category.goalAligned).accent;
    final maint = categoryStyle(context, Category.maintenance).accent;
    final off = categoryStyle(context, Category.offPlan).accent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: Space.md, runSpacing: Space.xs, children: [
          for (final (c, color) in [
            (Category.goalAligned, goal),
            (Category.maintenance, maint),
            (Category.offPlan, off),
          ])
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 12, height: 12, color: color),
              const SizedBox(width: Space.xs),
              Text(categoryStyle(context, c).name, style: text.bodySmall),
            ]),
        ]),
        const SizedBox(height: Space.sm),
        SizedBox(
          key: const Key('stacked-bars'),
          height: _height + 52,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final w in weeks)
                Expanded(
                  child: Semantics(
                    label: 'Week of ${w.key}${w.finished ? '' : ', so far'}: '
                        '${w.tasksDone} tasks completed, ${w.goalAligned} '
                        'goal-aligned, ${w.maintenance} maintenance, '
                        '${w.offPlan} off-plan.',
                    excludeSemantics: true,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text('${w.tasksDone}', style: text.labelSmall),
                          const SizedBox(height: 2),
                          Opacity(
                            opacity: w.finished ? 1 : .55,
                            child: Column(children: [
                              seg(w.offPlan, off),
                              seg(w.maintenance, maint),
                              seg(w.goalAligned, goal),
                            ]),
                          ),
                          const SizedBox(height: 4),
                          Container(height: 1, color: colors.rule),
                          const SizedBox(height: 2),
                          Text(_short(w.weekStart),
                              style: text.labelSmall
                                  ?.copyWith(color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A bar for each week: the share of the committed tasks that were done.
class _CompletionBars extends StatelessWidget {
  const _CompletionBars({required this.weeks});

  final List<WeekMetrics> weeks;

  static const double _height = 100;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = context.tefteri;
    final text = Theme.of(context).textTheme;
    return SizedBox(
      key: const Key('completion-bars'),
      height: _height + 52,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final w in weeks)
            Expanded(
              child: Semantics(
                label: 'Week of ${w.key}${w.finished ? '' : ', so far'}: '
                    '${w.completionPercent == null ? 'no committed task' : '${w.completionPercent}% of the committed tasks done'}.',
                excludeSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                          w.completionPercent == null
                              ? '-'
                              : '${w.completionPercent}%',
                          style: text.labelSmall),
                      const SizedBox(height: 2),
                      Opacity(
                        opacity: w.finished ? 1 : .55,
                        child: Container(
                          height: _height * ((w.completionPercent ?? 0) / 100),
                          color: colors.done,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(height: 1, color: colors.rule),
                      const SizedBox(height: 2),
                      Text(_short(w.weekStart),
                          style: text.labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The exact numbers of every week, newest first.
class _NumbersTable extends StatelessWidget {
  const _NumbersTable({required this.weeks});

  final List<WeekMetrics> weeks;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.tefteri;
    const head = [
      'Week',
      'Tasks done',
      'Goal-aligned',
      'Maintenance',
      'Off-plan',
      'Goal-aligned %',
      'Committed done',
      'Completion',
      'Milestones done',
      'Themes',
    ];
    String pct(int? v) => v == null ? '-' : '$v%';
    TableRow row(List<String> cells, {bool header = false, LocalKey? key}) =>
        TableRow(
          key: key,
          decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.rule))),
          children: [
            for (final c in cells)
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: Space.sm, vertical: Space.xs),
                child: Text(c,
                    style: header
                        ? text.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w700)
                        : text.bodySmall),
              ),
          ],
        );
    return SingleChildScrollView(
      key: const Key('numbers-table'),
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        children: [
          row(head, header: true),
          for (final w in weeks.reversed)
            row(
              [
                '${dateKey(w.weekStart)}${w.finished ? '' : ' (so far)'}',
                '${w.tasksDone}',
                '${w.goalAligned}',
                '${w.maintenance}',
                '${w.offPlan}',
                pct(w.goalAlignedPercent),
                w.committedTasks == 0
                    ? '-'
                    : '${w.committedDone} of ${w.committedTasks}',
                pct(w.completionPercent),
                w.milestonesCommitted == 0 && w.milestonesFinished == 0
                    ? '-'
                    : '${w.milestonesDone} of ${w.milestonesCommitted}'
                        '${w.milestonesFinished > w.milestonesDone ? ' (+${w.milestonesFinished - w.milestonesDone})' : ''}',
                '${w.themesActive}',
              ],
            ),
        ],
      ),
    );
  }
}
