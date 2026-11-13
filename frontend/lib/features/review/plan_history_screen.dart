/// Plan history: every plan, newest period first, with its review state.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_error.dart';
import '../../core/planning_models.dart';
import '../../core/shell.dart';
import '../../theme/theme.dart';
import '../../core/periods.dart';
import 'review_api.dart';
import 'review_models.dart';

/// Lists all plans; opening one shows its review. Plans are kept after
/// their period ends.
class PlanHistoryScreen extends ConsumerStatefulWidget {
  /// Creates the screen; [today] defaults to now (for the new-plan choices).
  const PlanHistoryScreen({this.today, this.period, this.year, super.key});

  /// Day used to offer periods in the new-plan dialog.
  final DateTime? today;

  /// Filter: `year`, `month` or `week`, or null.
  final String? period;

  /// Filter: the year of the stored reviews, or null.
  final int? year;

  @override
  ConsumerState<PlanHistoryScreen> createState() => _PlanHistoryScreenState();
}

class _PlanHistoryScreenState extends ConsumerState<PlanHistoryScreen> {
  String? _error;

  Future<void> _newPlan() async {
    final draft = await showDialog<_PlanDraft>(
      context: context,
      builder: (_) => _NewPlanDialog(today: widget.today ?? DateTime.now()),
    );
    if (draft == null) return;
    try {
      await ref.read(reviewApiProvider).createPlan(
          periodType: draft.type, periodStart: draft.start, title: draft.title);
    } on DioException catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
      return;
    }
    if (!mounted) return;
    setState(() => _error = null);
    ref.invalidate(planHistoryProvider);
  }

  String? get _filterLabel {
    final period = widget.period;
    final year = widget.year;
    if (period == null && year == null) return null;
    if (period == 'year' && year != null) return 'Year $year';
    return '${period ?? 'All'} ${year ?? ''}'.trim();
  }

  List<PlanHistoryEntry> _filtered(List<PlanHistoryEntry> plans) => [
        for (final p in plans)
          if ((widget.period == null || p.periodType == widget.period) &&
              (widget.year == null ||
                  DateTime.tryParse(p.periodStart)?.year == widget.year))
            p,
      ];

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(planHistoryProvider);
    return AppShell(
      title: 'Reviews',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null)
            ErrorBanner(
                message: _error!,
                onDismiss: () => setState(() => _error = null)),
          if (_filterLabel != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Chip(
                    key: const Key('history-filter'),
                    label: Text(_filterLabel!),
                  ),
                  TextButton(
                    key: const Key('history-clear-filter'),
                    onPressed: () => context.go('/review'),
                    child: const Text('Clear filter'),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                key: const Key('new-plan'),
                onPressed: _newPlan,
                icon: const Icon(Icons.add),
                label: const Text('New plan'),
              ),
            ),
          ),
          Expanded(
            child: history.when(
              loading: () => const Loading(),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(apiErrorMessage(e), key: const Key('load-error')),
                    TextButton(
                      key: const Key('reload-button'),
                      onPressed: () => ref.invalidate(planHistoryProvider),
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
              data: (plans) {
                final shown = _filtered(plans);
                return shown.isEmpty
                    ? const EmptyState(
                        icon: Icons.auto_stories_outlined,
                        message: 'No plans yet. Add a plan for a year, '
                            'a month or a week.')
                    : ListView(
                        children: [for (final p in shown) _tile(p)],
                      );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(PlanHistoryEntry p) {
    final status = p.plannedCount == null
        ? (p.periodEnded ? 'Ended. No review yet.' : 'In progress.')
        : '${p.completedCount} of ${p.plannedCount} done'
            '${p.hasRetrospective ? ' - retrospective saved' : ''}';
    return ListTile(
      key: Key('plan-${p.planId}'),
      leading: Icon(p.periodEnded ? Icons.history : Icons.flag_outlined),
      title: Text(p.title),
      subtitle: Text('${periodLabel(p.periodType, p.periodStart)} - $status'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.go('/review/${p.planId}'),
    );
  }
}

class _PlanDraft {
  const _PlanDraft(this.type, this.start, this.title);

  final String type;
  final String start;
  final String title;
}

/// Periods offered for a new plan: a few past ones, the current one and the
/// next ones, newest first.
List<PeriodChoice> planPeriods(String type, DateTime today) {
  final out = <PeriodChoice>[];
  switch (type) {
    case 'year':
      for (var y = today.year + 1; y >= today.year - 3; y--) {
        out.add(PeriodChoice(
            label: '$y', type: 'year', start: dateKey(DateTime(y))));
      }
    case 'month':
      for (var m = 2; m >= -12; m--) {
        final d = DateTime(today.year, today.month + m);
        out.add(PeriodChoice(
            label: '${monthName(d.month)} ${d.year}',
            type: 'month',
            start: dateKey(d)));
      }
    default:
      final monday = weekStartOf(today);
      for (var w = 2; w >= -8; w--) {
        final d = DateTime(monday.year, monday.month, monday.day + 7 * w);
        out.add(PeriodChoice(
            label: 'Week of ${dateKey(d)}', type: 'week', start: dateKey(d)));
      }
  }
  return out;
}

class _NewPlanDialog extends StatefulWidget {
  const _NewPlanDialog({required this.today});

  final DateTime today;

  @override
  State<_NewPlanDialog> createState() => _NewPlanDialogState();
}

class _NewPlanDialogState extends State<_NewPlanDialog> {
  final _title = TextEditingController();
  String _type = 'year';
  late String _start = _current('year');

  String _current(String type) {
    final t = widget.today;
    return switch (type) {
      'year' => dateKey(DateTime(t.year)),
      'month' => dateKey(DateTime(t.year, t.month)),
      _ => dateKey(weekStartOf(t)),
    };
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New plan'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('plan-title'),
            controller: _title,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          DropdownButtonFormField<String>(
            key: const Key('plan-type'),
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Period type'),
            items: const [
              DropdownMenuItem(value: 'year', child: Text('Year')),
              DropdownMenuItem(value: 'month', child: Text('Month')),
              DropdownMenuItem(value: 'week', child: Text('Week')),
            ],
            onChanged: (v) => setState(() {
              _type = v!;
              _start = _current(_type);
            }),
          ),
          DropdownButtonFormField<String>(
            key: ValueKey('plan-period-$_type'),
            initialValue: _start,
            decoration: const InputDecoration(labelText: 'Period'),
            items: [
              for (final c in planPeriods(_type, widget.today))
                DropdownMenuItem(value: c.start, child: Text(c.label)),
            ],
            onChanged: (v) => setState(() => _start = v!),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('plan-save'),
          onPressed: () {
            final title = _title.text.trim();
            if (title.isEmpty) return;
            Navigator.of(context).pop(_PlanDraft(_type, _start, title));
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
