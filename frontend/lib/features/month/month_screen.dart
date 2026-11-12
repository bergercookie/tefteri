/// Monthly planning around theme projects, milestone targets and key results.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_error.dart';
import '../../core/planning_models.dart';
import '../../core/shell.dart';
import '../../theme/theme.dart';
import '../checklists/checklist_panel.dart';
import '../projects/term_hint.dart';
import '../../core/periods.dart';
import 'earlier_format_view.dart';
import 'focus_change_dialog.dart';
import 'focus_history_sheet.dart';
import 'focus_section.dart';
import 'month_api.dart';
import 'month_controller.dart';
import 'month_models.dart';
import 'suggestions_card.dart';
import 'theme_picker.dart';

/// Shows planning for the month that holds [initialDate].
class MonthScreen extends ConsumerStatefulWidget {
  /// Creates the page; defaults to the current month.
  const MonthScreen({this.initialDate, super.key});

  /// An initial day inside the month.
  final DateTime? initialDate;

  @override
  ConsumerState<MonthScreen> createState() => _MonthScreenState();
}

class _MonthScreenState extends ConsumerState<MonthScreen> {
  late DateTime _first;
  String? _draftMonth;
  List<Map<String, Object?>> _draft = [];
  final Map<String, int?> _pendingTargets = {};
  final Set<String> _invalidTargets = {};
  String? _error;
  bool _saving = false;

  String get _month => '${_first.year.toString().padLeft(4, '0')}-'
      '${_first.month.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    final day = widget.initialDate ?? DateTime.now();
    _first = DateTime(day.year, day.month, 1);
  }

  void _initializeDraft(MonthPlan plan) {
    if (_draftMonth == plan.month) return;
    _draftMonth = plan.month;
    _error = null;
    if (plan.focusKnown) {
      _draft = [
        for (final entry in plan.activeEntries) _entryMap(entry),
      ];
      return;
    }
    _draft = [];
  }

  Map<String, Object?> _entryMap(MonthEntry entry) => {
        'id': entry.id,
        'project_id': entry.projectId,
        'connection_id': entry.connectionId,
        'name': entry.name,
        'target': entry.target,
        'counts_from': entry.countsFrom,
        'left_on': entry.leftOn,
        'status': entry.status,
        'done': entry.done,
        'earlier_not_counted': entry.earlierNotCounted,
        'marker': entry.marker,
        'orphaned': entry.orphaned,
        'label_changed': entry.labelChanged,
        'linked_key_results': entry.linkedKeyResults,
        'last_month_done': entry.lastMonthDone,
      };

  Map<String, Object?> _suggestionMap(MonthSuggestion suggestion) => {
        'id': '',
        'project_id': suggestion.projectId,
        'connection_id': '',
        'name': suggestion.name,
        'target': suggestion.target,
        'counts_from': '$_month-01',
        'status': 'in_focus',
        'done': 0,
        'earlier_not_counted': 0,
        'marker': null,
        'orphaned': null,
        'label_changed': null,
        'linked_key_results': 0,
        'last_month_done': 0,
      };

  MonthTheme _themeFromMap(Map<String, Object?> entry) => MonthTheme.fromJson({
        'project_id': entry['project_id'],
        'connection_id': entry['connection_id'],
        'connection_name': entry['connection_name'] ?? '',
        'name': entry['name'],
        'in_focus': true,
        'left_this_month': false,
        'last_month_done': entry['last_month_done'] ?? 0,
        'key_result_ids': const [],
      });

  void _editSelection(List<MonthTheme> selected) {
    final previous = {
      for (final entry in _draft) '${entry['project_id']}': entry,
    };
    setState(() {
      _invalidTargets.remove('suggestion');
      _draft = [
        for (final theme in selected)
          {
            ...?previous[theme.projectId],
            'project_id': theme.projectId,
            'connection_id': theme.connectionId,
            'connection_name': theme.connectionName,
            'name': theme.name,
            'target': previous[theme.projectId]?['target'],
            'last_month_done': theme.lastMonthDone,
            'status': 'in_focus',
            'done': previous[theme.projectId]?['done'] ?? 0,
            'counts_from': '$_month-01',
          },
      ];
    });
  }

  Future<void> _openPicker(MonthPlan plan) async {
    final savedCurrent = plan.focusKnown && plan.state == 'current';
    final selected = <MonthTheme>[];
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
          child: Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: ThemePicker(
              month: _month,
              initialSelection:
                  savedCurrent ? const [] : _draft.map(_themeFromMap).toList(),
              onSelectionChanged: (items) {
                if (savedCurrent) {
                  selected
                    ..clear()
                    ..addAll(items);
                } else {
                  _editSelection(items);
                }
              },
              onClose: () => Navigator.pop(context),
            ),
          ),
        ),
      ),
    );
    if (!mounted || selected.isEmpty) return;
    for (final theme in selected) {
      if (savedCurrent) {
        await _applyFocusChange(
          plan,
          kind: 'add',
          inProjectId: theme.projectId,
          target: null,
        );
      }
    }
  }

  Future<void> _swapTheme(MonthPlan plan, Map<String, Object?> entry) async {
    MonthTheme? selected;
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
          child: Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: ThemePicker(
              month: _month,
              initialSelection: const [],
              onSelectionChanged: (items) {
                selected = items.isEmpty ? null : items.first;
              },
              onClose: () => Navigator.pop(context),
            ),
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    await _applyFocusChange(
      plan,
      kind: 'swap',
      outProjectId: '${entry['project_id']}',
      inProjectId: selected!.projectId,
    );
  }

  Future<void> _applyFocusChange(
    MonthPlan plan, {
    required String kind,
    String? outProjectId,
    String? inProjectId,
    Object? target,
  }) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final api = ref.read(monthApiProvider);
      final preview = await api.change(
        _month,
        kind: kind,
        outProjectId: outProjectId,
        inProjectId: inProjectId,
        target: target,
        dryRun: true,
      );
      if (!mounted) return;
      final confirm = await showFocusChangeDialog(
        context,
        kind: kind,
        effect: monthJsonMap(preview['effect']),
      );
      if (confirm != true || !mounted) return;
      final result = await api.change(
        _month,
        kind: kind,
        outProjectId: outProjectId,
        inProjectId: inProjectId,
        target: target,
      );
      if (!mounted) return;
      if (kind == 'target' && outProjectId != null) {
        final index =
            _draft.indexWhere((entry) => entry['project_id'] == outProjectId);
        if (index >= 0) _draft[index]['target'] = target;
        _pendingTargets.remove(outProjectId);
      }
      ref.invalidate(monthThemesProvider(_month));
      await ref.read(monthPlanProvider(_month).notifier).load();
      if (!mounted) return;
      final batch = '${result['batch_id']}';
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          key: const Key('focus-undo-snackbar'),
          content: Text(
              '${monthJsonMap(result['effect'])['message'] ?? 'Focus changed.'}'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              await ref.read(monthPlanProvider(_month).notifier).undo(batch);
              if (mounted) {
                ref.invalidate(monthThemesProvider(_month));
              }
            },
          ),
        ));
    } catch (error) {
      if (mounted) setState(() => _error = apiErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _savePlan(MonthPlan plan) async {
    if (_pendingTargets.isNotEmpty &&
        plan.focusKnown &&
        plan.state == 'current') {
      for (final change in _pendingTargets.entries.toList()) {
        await _applyFocusChange(
          plan,
          kind: 'target',
          outProjectId: change.key,
          target: change.value,
        );
        if (!mounted) return;
        if (_error != null) return;
      }
      setState(_pendingTargets.clear);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final entries = [
        for (final entry in _draft)
          {
            'project_id': '${entry['project_id']}',
            'target': entry['target'],
          },
      ];
      final api = ref.read(monthApiProvider);
      final preview = await api.saveFocus(_month, entries, dryRun: true);
      if (!mounted) return;
      final effect = monthJsonMap(preview['effect']);
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Save this month’s focus?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${effect['message'] ?? 'This saves the selected focus.'}'),
              if (preview['count_note'] == 'above' ||
                  preview['count_note'] == 'below' ||
                  preview['count_note'] == 'empty')
                const Padding(
                  padding: EdgeInsets.only(top: Space.sm),
                  child: Text(
                    'Three to five themes is usual. This guidance does not block saving.',
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep editing')),
            FilledButton(
                key: const Key('confirm-save-focus'),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Save focus')),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
      await ref.read(monthPlanProvider(_month).notifier).saveFocus(entries);
      if (!mounted) return;
      setState(() => _pendingTargets.clear());
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Monthly focus saved.')));
    } catch (error) {
      if (mounted) setState(() => _error = apiErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _shift(int amount) {
    setState(() {
      _first = DateTime(_first.year, _first.month + amount, 1);
      _draftMonth = null;
      _draft = [];
      _pendingTargets.clear();
      _invalidTargets.clear();
      _error = null;
    });
  }

  Widget _monthHeader() {
    final now = DateTime.now();
    return Row(
      children: [
        IconButton(
          key: const Key('prev-period'),
          tooltip: 'Previous month',
          onPressed: () => _shift(-1),
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${monthName(_first.month)} ${_first.year}',
                key: const Key('period-label'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (_first.year == now.year && _first.month == now.month)
                Text('This month',
                    style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        IconButton(
          key: const Key('next-period'),
          tooltip: 'Next month',
          onPressed: () => _shift(1),
          icon: const Icon(Icons.chevron_right),
        ),
        TextButton(
          key: const Key('today-button'),
          onPressed: () {
            final today = DateTime.now();
            setState(() {
              _first = DateTime(today.year, today.month, 1);
              _draftMonth = null;
              _draft = [];
              _pendingTargets.clear();
              _invalidTargets.clear();
            });
          },
          child: const Text('Today'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final planState = ref.watch(monthPlanProvider(_month));
    ref.listen(monthPlanProvider(_month), (previous, next) {
      next.whenData((plan) {
        if (_draftMonth != plan.month) setState(() => _initializeDraft(plan));
      });
    });
    return AppShell(
      title: 'Month',
      body: planState.when(
        loading: () => const Loading(),
        error: (error, _) => Center(
          child: EmptyState(
            message: apiErrorMessage(error),
            action: TextButton(
              onPressed: () =>
                  ref.read(monthPlanProvider(_month).notifier).load(),
              child: const Text('Try again'),
            ),
          ),
        ),
        data: (plan) {
          _initializeDraft(plan);
          final past = plan.state == 'past';
          final legacyOnly = plan.earlierFormat &&
              past &&
              !plan.focusKnown &&
              plan.entries.isEmpty;
          final savedCurrent = plan.focusKnown && plan.state == 'current';
          final entries = plan.focusKnown
              ? [
                  for (final entry in plan.activeEntries) _entryMap(entry),
                ].map((entry) {
                  final draft = _draft.firstWhere(
                      (item) => item['project_id'] == entry['project_id'],
                      orElse: () => entry);
                  return {...entry, ...draft};
                }).toList()
              : _draft;
          final suggestions = ref.watch(monthSuggestionsProvider(_month));
          return LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth >= 860;
            return SingleChildScrollView(
              padding: EdgeInsets.all(wide ? Space.xl : Space.lg),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 920),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _monthHeader(),
                      const SizedBox(height: Space.md),
                      PlanningChecklist(
                        kind: ChecklistKind.month,
                        day: _first,
                        card: true,
                      ),
                      const TermHint(
                        id: 'monthly-planning-terms',
                        title: 'Monthly planning',
                        terms: monthlyFocusTerms,
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Space.md),
                          child: Text(_error!,
                              key: const Key('month-action-error'),
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error)),
                        ),
                      if (legacyOnly) ...[
                        EarlierFormatView(month: _month),
                      ] else ...[
                        if (!plan.focusKnown && plan.state != 'past')
                          suggestions.when(
                            loading: () => const Padding(
                              padding: EdgeInsets.all(Space.md),
                              child: Loading(),
                            ),
                            error: (error, _) => EmptyState(
                              message: apiErrorMessage(error),
                              action: TextButton(
                                onPressed: () => ref.invalidate(
                                    monthSuggestionsProvider(_month)),
                                child: const Text('Try again'),
                              ),
                            ),
                            data: (data) => SuggestionsCard(
                              key: ValueKey('suggestions-${data.fromMonth}'),
                              suggestions: data,
                              showItems: false,
                              onChanged: (items) {
                                setState(() {
                                  _draft = [
                                    for (final item in items)
                                      _suggestionMap(item),
                                  ];
                                });
                              },
                              onValidityChanged: (valid) {
                                setState(() {
                                  if (valid) {
                                    _invalidTargets.remove('suggestion');
                                  } else {
                                    _invalidTargets.add('suggestion');
                                  }
                                });
                              },
                            ),
                          ),
                        if (!plan.focusKnown && plan.state != 'past')
                          FocusSection(
                            entries: entries,
                            keyResults: plan.keyResults,
                            onTargetChanged: (id, value) {
                              setState(() {
                                final index = _draft.indexWhere(
                                    (entry) => entry['project_id'] == id);
                                if (index >= 0) _draft[index]['target'] = value;
                              });
                            },
                            onTargetValidityChanged: (id, valid) {
                              setState(() {
                                if (valid) {
                                  _invalidTargets.remove(id);
                                } else {
                                  _invalidTargets.add(id);
                                }
                              });
                            },
                            onChooseThemes: () => _openPicker(plan),
                          )
                        else
                          FocusSection(
                            entries: entries,
                            keyResults: plan.keyResults,
                            readOnly: past,
                            onTargetChanged: (id, value) {
                              setState(() {
                                final index = _draft.indexWhere(
                                    (entry) => entry['project_id'] == id);
                                if (index >= 0) _draft[index]['target'] = value;
                                if (savedCurrent) _pendingTargets[id] = value;
                              });
                            },
                            onTargetValidityChanged: (id, valid) {
                              setState(() {
                                if (valid) {
                                  _invalidTargets.remove(id);
                                } else {
                                  _invalidTargets.add(id);
                                }
                              });
                            },
                            onChooseThemes: () => _openPicker(plan),
                            onSwap: savedCurrent
                                ? (entry) => _swapTheme(plan, entry)
                                : null,
                            onRemove: savedCurrent
                                ? (entry) => _applyFocusChange(
                                      plan,
                                      kind: 'remove',
                                      outProjectId: '${entry['project_id']}',
                                    )
                                : null,
                          ),
                        _PlanningFlags(
                          keyResults: plan.keyResults,
                          onOpenPicker: () => _openPicker(plan),
                        ),
                        if (savedCurrent && _pendingTargets.isNotEmpty)
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton(
                              key: const Key('apply-target-changes'),
                              onPressed: _saving || _invalidTargets.isNotEmpty
                                  ? null
                                  : () => _savePlan(plan),
                              child: const Text('Apply target changes'),
                            ),
                          )
                        else if (!past && !savedCurrent)
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton(
                              key: const Key('save-focus'),
                              onPressed: _saving || _invalidTargets.isNotEmpty
                                  ? null
                                  : () => _savePlan(plan),
                              child: Text(_saving ? 'Saving…' : 'Save focus'),
                            ),
                          ),
                        if (plan.focusKnown)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              key: const Key('focus-history'),
                              onPressed: () => showFocusHistorySheet(
                                context,
                                month: _month,
                                onUndo: (batch) async {
                                  await ref
                                      .read(monthPlanProvider(_month).notifier)
                                      .undo(batch);
                                  if (mounted) {
                                    ref.invalidate(monthThemesProvider(_month));
                                  }
                                },
                              ),
                              icon: const Icon(Icons.history),
                              label: const Text('Change history'),
                            ),
                          ),
                        if (!legacyOnly && plan.state != 'future')
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              key: const Key('open-month-review'),
                              onPressed: () =>
                                  context.go('/month/review?date=$_month-01'),
                              icon: const Icon(Icons.rate_review_outlined),
                              label: Text(plan.review['stored'] == true
                                  ? 'Open monthly review'
                                  : 'Review this month'),
                            ),
                          ),
                        if (plan.countNote == 'empty')
                          Text(
                              'No themes selected. You can still plan this month.',
                              style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ],
                  ),
                ),
              ),
            );
          });
        },
      ),
    );
  }
}

class _PlanningFlags extends StatelessWidget {
  const _PlanningFlags({
    required this.keyResults,
    required this.onOpenPicker,
  });

  final List<Map<String, dynamic>> keyResults;
  final VoidCallback onOpenPicker;

  @override
  Widget build(BuildContext context) {
    final unlinked = keyResults.where((result) =>
        (result['flags'] as List? ?? const []).any((flag) =>
            flag is Map && flag['code'] == 'no_usable_theme' ||
            flag == 'no_usable_theme'));
    if (unlinked.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Space.md),
        for (final result in unlinked)
          Container(
            key: Key('planning-key-result-${result['id']}'),
            padding: const EdgeInsets.all(Space.md),
            decoration: BoxDecoration(
              border: Border.all(color: context.tefteri.rule),
              borderRadius: BorderRadius.circular(Corner.md),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${result['goal_title']}: ${result['metric']} · No usable theme',
                  ),
                ),
                TextButton(
                  onPressed: () => context.go('/annual'),
                  child: const Text('Annual plan'),
                ),
                TextButton(
                  onPressed: onOpenPicker,
                  child: const Text('Open picker'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
