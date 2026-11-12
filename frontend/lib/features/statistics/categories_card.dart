/// The card that shows what was completed in a week, a month or a year, split
/// into the three work categories.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_error.dart';
import '../../core/planning_models.dart';
import '../../theme/theme.dart';
import '../projects/term_hint.dart';
import '../projects/unsorted_card.dart';
import '../settings/sync_controller.dart';
import '../../core/periods.dart';
import '../weekly/weekly_widgets.dart';
import 'category_counts_row.dart';
import 'drilldown_screen.dart';
import 'proportion_bar.dart';
import 'statistics_models.dart';
import 'statistics_providers.dart';

/// The line on the week page that says what goal-aligned means.
const weekHelperLine =
    'Goal-aligned means work in a milestone you committed to this week.';

/// Three counts, one bar and the quiet lines for the [period] (`week`,
/// `month` or `year`) that holds [day].
///
/// Every count and every bar segment opens the tasks behind it. The numbers
/// come from the server and are the last stored ones also while a sync runs or
/// has failed: nothing here is ever switched off.
class CategoriesCard extends ConsumerWidget {
  /// Creates the card.
  const CategoriesCard({required this.period, required this.day, super.key});

  /// `week`, `month` or `year`.
  final String period;

  /// Any day inside the period.
  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = StatsQuery(period, periodDayKey(period, day));
    // A sync that ends may have found new tasks: read the numbers again.
    ref.listen<SyncState>(syncControllerProvider, (prev, next) {
      if (prev != null && prev.busy && !next.busy) {
        ref.invalidate(statisticsProvider);
        ref.invalidate(taskListProvider);
      }
    });
    final async = ref.watch(statisticsProvider(query));
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('categories-card'),
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        border: Border.all(color: context.tefteri.rule),
        borderRadius: BorderRadius.circular(Corner.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Completed work', style: text.titleMedium),
          if (period == 'week') ...[
            const SizedBox(height: Space.xs),
            Text(weekHelperLine,
                style:
                    text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
          const SizedBox(height: Space.md),
          async.when(
            loading: () => const Padding(
                padding: EdgeInsets.all(Space.xl), child: Loading()),
            error: (e, _) => _LoadError(
              message: apiErrorMessage(e),
              period: period,
              onRetry: () => ref.invalidate(statisticsProvider(query)),
            ),
            data: (s) => _Body(summary: s, query: query, day: day),
          ),
        ],
      ),
    );
  }
}

String _periodNoun(String period) => period;

class _LoadError extends StatelessWidget {
  const _LoadError(
      {required this.message, required this.period, required this.onRetry});

  final String message;
  final String period;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      key: const Key('categories-error'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tefteri could not load the numbers for this '
            '${_periodNoun(period)}.'),
        const SizedBox(height: Space.xs),
        Text(message,
            style: text.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        TextButton(
          key: const Key('categories-retry'),
          onPressed: onRetry,
          child: const Text('Try again'),
        ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.summary, required this.query, required this.day});

  final StatisticsSummary summary;
  final StatsQuery query;
  final DateTime day;

  void _open(BuildContext context, Category c) =>
      openDrilldown(context, summary.period, query.day, c);

  @override
  Widget build(BuildContext context) {
    final s = summary;
    if (!s.available) return const _Unavailable();
    final empty = s.empty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (empty == null) ...[
          // One box for every term on the card: stacked boxes push the
          // numbers below the fold on the first visit.
          TermHint(
              id: 'category-terms',
              title: 'What these words mean',
              terms: [
                ...categoryTerms,
                if (s.unsorted > 0) ...unsortedTaskTerms,
                if (s.hidden > 0) ...hiddenTaskTerms,
              ]),
          CategoryCountsRow(
            counts: s.counts,
            percentages: s.percentages,
            onSelect: (c) => _open(context, c),
          ),
          const SizedBox(height: Space.md),
          ProportionBar(
            counts: s.counts,
            percentages: s.percentages,
            legend: false,
            onSelect: (c) => _open(context, c),
          ),
          const SizedBox(height: Space.sm),
          Text('${plural(s.total, 'task')} completed',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          if (s.unsorted > 0) _UnsortedLine(count: s.unsorted),
          if (s.hidden > 0)
            _HiddenLine(
                count: s.hidden, onTap: () => _open(context, Category.hidden)),
        ] else
          _Empty(summary: s, empty: empty, day: day),
        const SizedBox(height: Space.md),
        _SyncLine(sync: s.sync),
      ],
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Row(
      key: const Key('categories-unavailable'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 20, color: scheme.onSurfaceVariant),
        const SizedBox(width: Space.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tefteri cannot read your weekly plan right now.',
                  style: text.bodyMedium),
              const SizedBox(height: Space.xs),
              Text(
                'It shows no numbers instead of guessing them. Sync again, '
                'or open this page again in a moment.',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.summary, required this.empty, required this.day});

  final StatisticsSummary summary;
  final StatEmpty empty;
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final String message;
    final String? label;
    final VoidCallback? go;
    if (empty.noLabels) {
      message = 'No project has a label yet, so Tefteri cannot sort your work.';
      label = 'Label your projects';
      go = () => openProjects(context);
    } else {
      message = 'No tasks were completed this ${_periodNoun(summary.period)}.';
      label = empty.action == 'plan_week' ? 'Plan your week' : null;
      go = () => GoRouter.maybeOf(context)
          ?.go('/week/plan?date=${dateKey(weekStartOf(day))}');
    }
    return EmptyState(
      key: const Key('categories-empty'),
      message: message,
      messageKey: const Key('categories-empty-message'),
      action: label == null
          ? null
          : OutlinedButton(
              key: const Key('categories-empty-action'),
              onPressed: go,
              child: Text(label),
            ),
    );
  }
}

class _UnsortedLine extends StatelessWidget {
  const _UnsortedLine({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final line = count == 1
        ? '1 off-plan task is unsorted: its project has no label.'
        : '$count of the off-plan tasks are unsorted: their projects have no '
            'label.';
    return Padding(
      padding: const EdgeInsets.only(top: Space.xs),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: Space.xs,
        children: [
          Text(line,
              style: text.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          TextButton(
            key: const Key('unsorted-label-projects'),
            style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: Space.xs)),
            onPressed: () => openProjects(context),
            child: const Text('Label your projects'),
          ),
        ],
      ),
    );
  }
}

class _HiddenLine extends StatelessWidget {
  const _HiddenLine({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final line = count == 1
        ? '1 task in an ignored project is not counted'
        : '$count tasks in ignored projects are not counted';
    return Padding(
      padding: const EdgeInsets.only(top: Space.xs),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Semantics(
          button: true,
          label: line,
          excludeSemantics: true,
          onTap: onTap,
          child: InkWell(
            key: const Key('hidden-line'),
            onTap: onTap,
            excludeFromSemantics: true,
            borderRadius: BorderRadius.circular(Corner.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xs),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.visibility_off_outlined,
                      size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: Space.xs),
                  Flexible(
                    child: Text(line,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            decoration: TextDecoration.underline)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SyncLine extends StatelessWidget {
  const _SyncLine({required this.sync});

  final StatSync sync;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final quiet = text.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final at = sync.lastSyncedAt?.toLocal();
    final failure = switch (sync.outcome) {
      'unreachable' => 'The last sync failed: Tefteri could not reach your '
          'task app.',
      'auth_expired' => 'The last sync failed: your task app sign-in has '
          'expired.',
      'ok' || null => null,
      _ => 'The last sync failed.',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.sync, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: Space.xs),
            Flexible(
              child: Text(
                at == null
                    ? 'Not synced yet'
                    : 'Last synced ${dateKey(at)} ${hhmm(at)}',
                key: const Key('last-sync'),
                style: quiet,
              ),
            ),
          ],
        ),
        if (failure != null)
          Padding(
            key: const Key('sync-failed'),
            padding: const EdgeInsets.only(top: Space.xs),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: Space.xs,
              children: [
                Icon(Icons.sync_problem_outlined,
                    size: 16, color: scheme.onSurfaceVariant),
                Text('$failure These are the last numbers it had.',
                    style: quiet),
                if (sync.outcome == 'auth_expired')
                  TextButton(
                    key: const Key('sync-open-connections'),
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding:
                            const EdgeInsets.symmetric(horizontal: Space.xs)),
                    onPressed: () =>
                        GoRouter.maybeOf(context)?.go('/settings/connections'),
                    child: const Text('Open connections'),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
