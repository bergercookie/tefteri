/// Start a new year from an earlier one (US5): the goals and unmet key
/// results of year N are offered as editable suggestions. Nothing is stored
/// until the user saves.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../theme/theme.dart';
import 'annual_controller.dart';
import 'annual_models.dart';
import 'annual_term_hint.dart';
import 'key_result_form.dart';

class _KrDraft {
  _KrDraft(this.source)
      : metric = TextEditingController(text: source.metric),
        start = TextEditingController(text: formatNumber(source.startValue)),
        target = TextEditingController(text: formatNumber(source.target)),
        deadline = TextEditingController(text: source.deadline);

  final SuggestedKeyResult source;
  final TextEditingController metric;
  final TextEditingController start;
  final TextEditingController target;
  final TextEditingController deadline;
  String? error;

  void dispose() {
    metric.dispose();
    start.dispose();
    target.dispose();
    deadline.dispose();
  }
}

class _GoalDraft {
  _GoalDraft(this.source) : title = TextEditingController(text: source.title);

  final SuggestedGoal source;
  final TextEditingController title;
  final List<_KrDraft> keyResults = [];
  String? error;

  void dispose() {
    title.dispose();
    for (final k in keyResults) {
      k.dispose();
    }
  }
}

/// The seed panel of [year].
class SeedPanel extends ConsumerStatefulWidget {
  /// Creates the panel. [onSave] stores the accepted goals (all or none) and
  /// throws on failure; [onDismiss] hides the panel for a blank plan.
  const SeedPanel({
    required this.year,
    required this.onSave,
    required this.onDismiss,
    super.key,
  });

  /// The new planning year.
  final int year;

  /// Stores the drafts, seeded from year N.
  final Future<void> Function(List<GoalDraft> goals, int fromYear) onSave;

  /// Hides the panel.
  final VoidCallback onDismiss;

  @override
  ConsumerState<SeedPanel> createState() => _SeedPanelState();
}

class _SeedPanelState extends ConsumerState<SeedPanel> {
  late int _from = widget.year - 1;
  late final _fromField = TextEditingController(text: '$_from');
  String? _fromError;
  final List<_GoalDraft> _drafts = [];
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _fromField.dispose();
    _clear();
    super.dispose();
  }

  void _clear() {
    for (final d in _drafts) {
      d.dispose();
    }
    _drafts.clear();
  }

  void _setFrom(String s) {
    final y = int.tryParse(s.trim());
    setState(() {
      if (y == null || s.trim().length != 4 || y >= widget.year) {
        _fromError = 'Write a year before ${widget.year}.';
        return;
      }
      _fromError = null;
      if (y != _from) {
        _from = y;
        _clear();
      }
    });
  }

  _GoalDraft _goal(SuggestedGoal g) {
    for (final d in _drafts) {
      if (d.source.goalId == g.goalId) return d;
    }
    final d = _GoalDraft(g);
    _drafts.add(d);
    return d;
  }

  bool _accepted(SuggestedGoal g, SuggestedKeyResult k) => _drafts.any((d) =>
      d.source.goalId == g.goalId &&
      d.keyResults.any((x) => x.source.keyResultId == k.keyResultId));

  void _accept(SuggestedGoal g, SuggestedKeyResult k) => setState(() {
        final d = _goal(g);
        if (!_accepted(g, k)) d.keyResults.add(_KrDraft(k));
      });

  List<GoalDraft>? _validate() {
    var ok = true;
    final out = <GoalDraft>[];
    for (final d in _drafts) {
      final title = d.title.text.trim();
      d.error = title.isEmpty ? 'Write the goal.' : null;
      ok &= d.error == null;
      final krs = <KeyResultDraft>[];
      for (final k in d.keyResults) {
        final yesNo = k.source.kind == 'yes_no';
        final start = yesNo ? 0.0 : parseNumber(k.start.text);
        final target = yesNo ? 1.0 : parseNumber(k.target.text);
        final day = parseDay(k.deadline.text);
        k.error = k.metric.text.trim().isEmpty
            ? 'Write what you measure.'
            : !yesNo && (start == null || target == null)
                ? 'The start value and the target must be numbers.'
                : !yesNo && start == target
                    ? 'The target must differ from the start value.'
                    : day == null
                        ? 'Write the deadline as YYYY-MM-DD.'
                        : day.year != widget.year
                            ? 'The deadline must fall in ${widget.year}.'
                            : null;
        if (k.error != null) {
          ok = false;
          continue;
        }
        krs.add(KeyResultDraft(
          metric: k.metric.text.trim(),
          kind: k.source.kind,
          startValue: start!,
          target: target!,
          deadline: isoDate(day!),
          updateSource: k.source.updateSource,
          themes: k.source.themes,
          seededFromKeyResultId: k.source.keyResultId,
        ));
      }
      out.add(GoalDraft(
          title: title, keyResults: krs, seededFromGoalId: d.source.goalId));
    }
    setState(() {});
    return ok ? out : null;
  }

  Future<void> _save() async {
    final goals = _validate();
    if (goals == null || goals.isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(goals, _from);
      if (mounted) setState(_clear);
    } catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final suggestions =
        ref.watch(planSuggestionsProvider((widget.year, _from)));
    return Container(
      key: const Key('seed-panel'),
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border.all(color: context.tefteri.rule),
        borderRadius: BorderRadius.circular(Corner.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: Space.md,
            runSpacing: Space.sm,
            children: [
              Text('Start from an earlier year', style: text.titleMedium),
              SizedBox(
                width: 140,
                child: TextField(
                  key: const Key('seed-from-year'),
                  controller: _fromField,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                      labelText: 'From year',
                      isDense: true,
                      errorText: _fromError,
                      errorMaxLines: 2),
                  onChanged: _setFrom,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          const AnnualTermHint(AnnualTerm.unmet),
          Text(
            'The goals of $_from and their unmet key results are suggestions. '
            'Nothing is stored until you save.',
            style: text.bodySmall,
          ),
          const SizedBox(height: Space.sm),
          suggestions.when(
            loading: () => const SizedBox(height: 60, child: Loading()),
            error: (e, _) =>
                Text(apiErrorMessage(e), style: TextStyle(color: scheme.error)),
            data: _suggestions,
          ),
          if (_drafts.isNotEmpty) ...[
            const SizedBox(height: Space.md),
            Text('New plan for ${widget.year}', style: text.titleSmall),
            for (final d in _drafts) _draft(d),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Text(_error!,
                  key: const Key('seed-error'),
                  style: TextStyle(color: scheme.error)),
            ),
          const SizedBox(height: Space.md),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: Space.sm,
            runSpacing: Space.xs,
            children: [
              TextButton(
                key: const Key('seed-dismiss'),
                onPressed: _saving ? null : widget.onDismiss,
                child: const Text('Dismiss all'),
              ),
              FilledButton(
                key: const Key('seed-save'),
                onPressed: _saving || _drafts.isEmpty ? null : _save,
                child: Text(_drafts.length == 1
                    ? 'Save 1 goal'
                    : 'Save ${_drafts.length} goals'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _suggestions(PlanSuggestions s) {
    final text = Theme.of(context).textTheme;
    if (!s.hasPlan || s.goals.isEmpty) {
      return Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: Space.sm,
        children: [
          Text('$_from has no plan.', key: const Key('seed-no-plan')),
          TextButton(
            key: const Key('seed-blank'),
            onPressed: widget.onDismiss,
            child: const Text('Start with a blank plan'),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final g in s.goals)
          Container(
            key: Key('seed-goal-${g.goalId}'),
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            decoration: BoxDecoration(
                border:
                    Border(bottom: BorderSide(color: context.tefteri.rule))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(g.title, style: text.bodyLarge)),
                    TextButton(
                      key: Key('seed-copy-goal-${g.goalId}'),
                      onPressed: _drafts.any((d) => d.source.goalId == g.goalId)
                          ? null
                          : () => setState(() => _goal(g)),
                      child: const Text('Copy goal'),
                    ),
                  ],
                ),
                for (final k in g.keyResults)
                  Padding(
                    key: Key('seed-kr-${k.keyResultId}'),
                    padding: const EdgeInsets.only(left: Space.lg),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            k.kind == 'yes_no'
                                ? '${k.metric}: unmet, last answer '
                                    '${k.startValue >= 0.5 ? 'Yes' : 'No'}'
                                    '${k.themes.isEmpty ? '' : ' · ${k.themes.map((t) => t.name).join(', ')}'}'
                                : '${k.metric}: unmet, last value '
                                    '${formatNumber(k.startValue)} of '
                                    '${formatNumber(k.target)}'
                                    '${k.themes.isEmpty ? '' : ' · ${k.themes.map((t) => t.name).join(', ')}'}',
                            style: text.bodySmall,
                          ),
                        ),
                        TextButton(
                          key: Key('seed-accept-kr-${k.keyResultId}'),
                          onPressed:
                              _accepted(g, k) ? null : () => _accept(g, k),
                          child: Text(_accepted(g, k) ? 'Accepted' : 'Accept'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _draft(_GoalDraft d) {
    final id = d.source.goalId;
    final scheme = Theme.of(context).colorScheme;
    Widget field(String key, TextEditingController c, String label,
            {double? width}) =>
        SizedBox(
          width: width,
          child: TextField(
            key: Key(key),
            controller: c,
            decoration: InputDecoration(labelText: label, isDense: true),
          ),
        );
    return Container(
      key: Key('draft-goal-$id'),
      margin: const EdgeInsets.only(top: Space.sm),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: context.tefteri.rule),
        borderRadius: BorderRadius.circular(Corner.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: Key('draft-goal-title-$id'),
                  controller: d.title,
                  decoration: InputDecoration(
                      labelText: 'Goal', isDense: true, errorText: d.error),
                ),
              ),
              IconButton(
                key: Key('draft-remove-goal-$id'),
                tooltip: 'Leave out this goal',
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  _drafts.remove(d);
                  d.dispose();
                }),
              ),
            ],
          ),
          for (final k in d.keyResults) ...[
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                field('draft-kr-metric-$id-${k.source.keyResultId}', k.metric,
                    'Metric',
                    width: 220),
                if (k.source.kind != 'yes_no') ...[
                  field('draft-kr-start-$id-${k.source.keyResultId}', k.start,
                      'Start value',
                      width: 110),
                  field('draft-kr-target-$id-${k.source.keyResultId}', k.target,
                      'Target',
                      width: 110),
                ],
                field('draft-kr-deadline-$id-${k.source.keyResultId}',
                    k.deadline, 'Deadline',
                    width: 130),
                IconButton(
                  key: Key('draft-remove-kr-$id-${k.source.keyResultId}'),
                  tooltip: 'Leave out this key result',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() {
                    d.keyResults.remove(k);
                    k.dispose();
                  }),
                ),
              ],
            ),
            if (k.error != null)
              Text(k.error!, style: TextStyle(color: scheme.error)),
          ],
        ],
      ),
    );
  }
}
