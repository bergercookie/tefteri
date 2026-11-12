/// The annual plan (`/annual`): the goals of one planning year, their key
/// results, the theme links and the three flags. Goals exist only here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/shell.dart';
import '../../theme/theme.dart';
import '../projects/effect_dialog.dart';
import 'annual_api.dart';
import 'annual_controller.dart';
import 'annual_models.dart';
import 'annual_term_hint.dart';
import 'goal_card.dart';
import 'key_result_form.dart';
import 'key_result_tile.dart';
import 'legacy_goals_view.dart';
import 'plan_history_view.dart';
import 'push_token_dialog.dart';
import 'retire_dialog.dart';
import 'seed_panel.dart';
import 'theme_picker.dart';
import 'value_dialog.dart';

/// Shows the annual plan of one year.
class AnnualScreen extends ConsumerStatefulWidget {
  /// Creates the screen; [initialYear] defaults to this year.
  const AnnualScreen({this.initialYear, this.today, super.key});

  /// The year to show first.
  final int? initialYear;

  /// Today, for tests; defaults to now.
  final DateTime? today;

  @override
  ConsumerState<AnnualScreen> createState() => _AnnualScreenState();
}

class _AnnualScreenState extends ConsumerState<AnnualScreen> {
  late int _year;
  final Set<int> _seedDismissed = {};
  bool _seedOpen = false;
  String? _error;

  DateTime get _today => widget.today ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _year = widget.initialYear ?? _today.year;
  }

  AnnualPlanController get _plan =>
      ref.read(annualPlanProvider(_year).notifier);

  void _go(int year) => setState(() {
        _year = year;
        _seedOpen = false;
        _error = null;
      });

  /// Runs [action]; a failure shows the server message at the top.
  Future<void> _run(Future<void> Function() action) async {
    setState(() => _error = null);
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
    }
  }

  void _undo(String? batch, String message) {
    if (batch == null || !mounted) return;
    final plan = _plan;
    showUndoSnackBar(context, message,
        onUndo: () => _run(() => plan.undo(batch)));
  }

  Future<void> _goalDialog({AnnualGoal? goal}) => showDialog<void>(
        context: context,
        builder: (_) => _GoalTitleDialog(
          initial: goal?.title ?? '',
          editing: goal != null,
          onSave: (title) => goal == null
              ? _plan.addGoals([GoalDraft(title: title)])
              : _plan.editGoal(goal.id, title),
        ),
      );

  void _addKeyResult(AnnualGoal goal, {String? metric}) {
    if (goal.activeKeyResults.length >= 3) {
      setState(() => _error = keyResultLimitMessage);
      return;
    }
    showKeyResultForm(context,
        year: _year,
        initialMetric: metric,
        onSave: (draft) => _plan.addKeyResult(goal.id, draft));
  }

  void _editKeyResult(KeyResult kr) => showKeyResultForm(
        context,
        year: _year,
        existing: kr,
        onSave: (d) async {
          final changed = d.metric != kr.metric ||
              d.target != kr.target ||
              d.deadline != kr.deadline ||
              d.updateSource != kr.updateSource;
          if (!changed) return;
          await _plan.editKeyResult(kr.id,
              metric: d.metric != kr.metric ? d.metric : null,
              target: d.target != kr.target ? d.target : null,
              deadline: d.deadline != kr.deadline ? d.deadline : null,
              updateSource:
                  d.updateSource != kr.updateSource ? d.updateSource : null);
        },
      );

  Future<void> _retireGoal(AnnualGoal goal) => _run(() async {
        final api = ref.read(annualApiProvider);
        final (effect, _) = await api.retireGoal(goal.id, dryRun: true);
        if (!mounted) return;
        final answer = await showRetireDialog(context,
            name: goal.title, effect: effect, goal: true);
        if (answer == null) return;
        final batch = await _plan.retireGoal(goal.id, reason: answer.reason);
        _undo(batch, 'Goal retired.');
      });

  Future<void> _retireKeyResult(KeyResult kr) => _run(() async {
        final api = ref.read(annualApiProvider);
        final (effect, _) = await api.retireKeyResult(kr.id, dryRun: true);
        if (!mounted) return;
        final answer = await showRetireDialog(context,
            name: kr.metric, effect: effect, goal: false);
        if (answer == null) return;
        final batch = await _plan.retireKeyResult(kr.id, reason: answer.reason);
        _undo(batch, 'Key result retired.');
      });

  Future<void> _linkThemes(KeyResult kr, {bool create = false}) =>
      _run(() async {
        final current = [
          for (final l in kr.activeLinks)
            if (l.usable) ThemeOption(projectId: l.projectId, name: l.name),
        ];
        final picked = await pickThemes(context,
            selected: current, startWithCreate: create);
        if (picked == null || !mounted) return;
        final ids = [for (final t in picked) t.projectId];
        final before = {for (final l in kr.activeLinks) l.projectId};
        if (before.length == ids.length && before.containsAll(ids)) return;
        final effect =
            await ref.read(annualApiProvider).previewThemes(kr.id, ids);
        if (!mounted) return;
        if (effect.ended.isNotEmpty &&
            !await showLinkEffectDialog(context, effect)) {
          return;
        }
        final batch = await _plan.setThemes(kr.id, ids);
        _undo(
            batch, effect.ended.isEmpty ? 'Themes linked.' : 'Links changed.');
      });

  void _updateValue(KeyResult kr) => showValueDialog(context,
      keyResult: kr,
      today: _today,
      onSave: (value, date) => _plan.addValue(kr.id, value, date: date));

  AnnualActions _actions(AnnualPlan plan) => AnnualActions(
        editable: plan.editable,
        addKeyResult: _addKeyResult,
        editGoal: (g) => _goalDialog(goal: g),
        retireGoal: _retireGoal,
        restoreGoal: (g) => _run(() => _plan.restoreGoal(g.id)),
        editKeyResult: _editKeyResult,
        linkThemes: _linkThemes,
        retireKeyResult: _retireKeyResult,
        restoreKeyResult: (k) => _run(() => _plan.restoreKeyResult(k.id)),
        updateValue: _updateValue,
      );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(annualPlanProvider(_year));
    return AppShell(
      title: 'Annual plan',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null)
            ErrorBanner(
                message: _error!,
                onDismiss: () => setState(() => _error = null)),
          Expanded(
            child: state.when(
              loading: () => const Loading(),
              error: (e, _) => EmptyState(
                messageKey: const Key('load-error'),
                message: apiErrorMessage(e),
                action: TextButton(
                  key: const Key('reload-button'),
                  onPressed: () => _plan.retry(),
                  child: const Text('Try again'),
                ),
              ),
              data: _body,
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(AnnualPlan plan) {
    final text = Theme.of(context).textTheme;
    final word = switch (plan.state) {
      'past' => 'Past year',
      'future' => 'Next year',
      _ => 'This year',
    };
    return Row(
      children: [
        IconButton(
          key: const Key('prev-year'),
          tooltip: 'Previous year',
          icon: const Icon(Icons.chevron_left),
          onPressed: () => _go(_year - 1),
        ),
        Column(
          key: const Key('year-label'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$_year', style: text.headlineSmall),
            Text(word, style: text.bodySmall),
          ],
        ),
        IconButton(
          key: const Key('next-year'),
          tooltip: 'Next year',
          icon: const Icon(Icons.chevron_right),
          onPressed: () => _go(_year + 1),
        ),
        if (_year != _today.year)
          TextButton(
            key: const Key('this-year'),
            onPressed: () => _go(_today.year),
            child: const Text('This year'),
          ),
      ],
    );
  }

  Widget _toolbar(AnnualPlan plan) => Wrap(
        spacing: Space.xs,
        runSpacing: Space.xs,
        children: [
          TextButton.icon(
            key: const Key('open-history'),
            onPressed: () => showPlanHistory(context,
                year: _year,
                plan: plan,
                onUndo: plan.editable ? _plan.undo : null),
            icon: const Icon(Icons.history, size: 18),
            label: const Text('History'),
          ),
          TextButton.icon(
            key: const Key('open-legacy-goals'),
            onPressed: () => showLegacyGoals(context),
            icon: const Icon(Icons.inventory_2_outlined, size: 18),
            label: const Text('Old goals'),
          ),
          TextButton.icon(
            key: const Key('open-push-token'),
            onPressed: () => showPushTokenDialog(context),
            icon: const Icon(Icons.key_outlined, size: 18),
            label: const Text('Push token'),
          ),
          if (plan.editable && plan.goals.isNotEmpty)
            TextButton.icon(
              key: const Key('open-suggestions'),
              onPressed: () => setState(() => _seedOpen = !_seedOpen),
              icon: const Icon(Icons.content_copy_outlined, size: 18),
              label: const Text('Copy from an earlier year'),
            ),
        ],
      );

  Widget _body(AnnualPlan plan) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final actions = _actions(plan);
    final seed = plan.editable &&
        (_seedOpen || (plan.goals.isEmpty && !_seedDismissed.contains(_year)));
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 720;
      return SingleChildScrollView(
        padding: EdgeInsets.all(wide ? Space.xl : Space.lg),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(plan),
                const SizedBox(height: Space.sm),
                const AnnualTermHint(AnnualTerm.planningYear),
                if (!plan.editable)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.sm),
                    child: Text(
                      '$_year is over. You can still enter values, but the '
                      'goals, key results and links cannot change.',
                      key: const Key('past-year-note'),
                      style: text.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                _toolbar(plan),
                const SizedBox(height: Space.md),
                if (seed) ...[
                  SeedPanel(
                    key: ValueKey('seed-$_year'),
                    year: _year,
                    onSave: (goals, from) async {
                      await _plan.addGoals(goals, seededFrom: from);
                      if (mounted) setState(() => _seedOpen = false);
                    },
                    onDismiss: () => setState(() {
                      _seedDismissed.add(_year);
                      _seedOpen = false;
                    }),
                  ),
                  const SizedBox(height: Space.lg),
                ],
                if (plan.goals.isEmpty)
                  EmptyState(
                    messageKey: const Key('annual-empty'),
                    message: plan.editable
                        ? 'No goals for $_year yet.'
                        : 'There were no goals in $_year.',
                    icon: Icons.flag_outlined,
                    action: plan.editable
                        ? FilledButton(
                            key: const Key('write-first-goal'),
                            onPressed: () => _goalDialog(),
                            child: const Text('Write a goal'),
                          )
                        : null,
                  )
                else ...[
                  for (final g in plan.goals)
                    GoalCard(key: ValueKey(g.id), goal: g, actions: actions),
                  if (plan.editable)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        key: const Key('add-goal'),
                        onPressed: () => _goalDialog(),
                        icon: const Icon(Icons.add),
                        label: const Text('Add a goal'),
                      ),
                    ),
                ],
                if (plan.retiredGoals.isNotEmpty) ...[
                  const SizedBox(height: Space.xl),
                  Text('Retired goals', style: text.titleMedium),
                  const SizedBox(height: Space.xs),
                  for (final g in plan.retiredGoals)
                    RetiredGoalRow(goal: g, actions: actions),
                ],
              ],
            ),
          ),
        ),
      );
    });
  }
}

class _GoalTitleDialog extends StatefulWidget {
  const _GoalTitleDialog(
      {required this.initial, required this.editing, required this.onSave});

  final String initial;
  final bool editing;
  final Future<void> Function(String title) onSave;

  @override
  State<_GoalTitleDialog> createState() => _GoalTitleDialogState();
}

class _GoalTitleDialogState extends State<_GoalTitleDialog> {
  late final _title = TextEditingController(text: widget.initial);
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final t = _title.text.trim();
    if (t.isEmpty) {
      setState(() => _error = 'Write the goal in one sentence.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(t);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = apiErrorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        key: const Key('goal-dialog'),
        title: Text(widget.editing ? 'Change the goal' : 'New goal'),
        content: SizedBox(
          width: 440,
          child: TextField(
            key: const Key('goal-title-field'),
            controller: _title,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Goal',
              hintText: 'Get better at open source',
              helperText: 'One loose sentence. Key results make it measurable.',
              errorText: _error,
            ),
            onSubmitted: (_) => _save(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('goal-title-save'),
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save'),
          ),
        ],
      );
}
