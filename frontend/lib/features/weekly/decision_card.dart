/// The card of one milestone in the weekly review: how it went, and what to
/// do with it. Four choices with one sentence each, an "expected" switch for a
/// recommit, "Mark as done", and the archive switch.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/project_chip.dart';
import '../../theme/theme.dart';
import '../projects/unsorted_card.dart';
import 'cap_notice.dart';
import 'close_dialog.dart';
import 'rescope_nudge.dart';
import 'weekly_api.dart';
import 'weekly_models.dart';
import 'weekly_widgets.dart';

/// Whether [p] still needs a decision, given the [answer] so far: it is not
/// finished, not closed and not marked done.
bool needsDecision(LookBackProject p, LookBackAnswer answer) =>
    !p.completed &&
    p.milestoneState != 'done' &&
    !p.closed &&
    !answer.markDone &&
    answer.decision == null;

/// The review card of one milestone.
class DecisionCard extends ConsumerStatefulWidget {
  /// Creates the card. [onChanged] gets the new answer.
  const DecisionCard({
    required this.project,
    required this.answer,
    required this.onChanged,
    required this.actions,
    super.key,
  });

  /// How the milestone went.
  final LookBackProject project;

  /// What the user chose so far.
  final LookBackAnswer answer;

  /// Called with the new answer.
  final ValueChanged<LookBackAnswer> onChanged;

  /// What the card can ask the screen to do.
  final WeeklyActions actions;

  @override
  ConsumerState<DecisionCard> createState() => _DecisionCardState();
}

class _DecisionCardState extends ConsumerState<DecisionCard> {
  CloseResult? _closeResult;
  ReopenResult? _reopened;
  String? _error;
  bool _busy = false;

  LookBackProject get _p => widget.project;
  LookBackAnswer get _a => widget.answer;
  bool get _closed => _p.closed || _a.decision == Decision.close;

  Future<void> _choose(Decision d) async {
    setState(() => _error = null);
    if (d == Decision.close) {
      final id = _p.milestoneId;
      if (id == null) return;
      final result =
          await showCloseDialog(context, milestoneId: id, name: _p.name);
      if (result == null || !mounted) return;
      setState(() {
        _closeResult = result;
        _reopened = null;
      });
      widget.onChanged(_a.withDecision(Decision.close));
      // Read the week again: the server now says the milestone is closed.
      await widget.actions.run((api) => api.state(widget.actions.week));
      return;
    }
    widget.onChanged(_a.withDecision(d));
  }

  Future<void> _reopen() async {
    final id = _p.milestoneId;
    if (id == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await ref.read(weeklyApiProvider).reopenMilestone(id);
      if (!mounted) return;
      setState(() {
        _reopened = r;
        _closeResult = null;
        _busy = false;
      });
      widget.onChanged(_a.withDecision(null));
      await widget.actions.run((api) => api.state(widget.actions.week));
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '${apiErrorMessage(e)} The milestone is still closed.';
      });
    }
  }

  Future<void> _markDone() async {
    final ok = await showMarkDoneDialog(context,
        name: _p.name, milestoneId: _p.milestoneId);
    if (ok && mounted) widget.onChanged(_a.copyWith(markDone: true));
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    final text = Theme.of(context).textTheme;
    final colors = context.tefteri;
    final quiet = text.bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    final left = p.leftover.length;
    final ratio = p.committed == 0 ? 0.0 : p.done / p.committed;
    final done = p.completed || p.milestoneState == 'done';
    return ProjectCard(
      name: p.name,
      color: p.color,
      key: Key('look-project-${p.id}'),
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(p.name, style: text.titleMedium)),
                if (done)
                  Chip(
                    key: Key('look-finished-${p.id}'),
                    avatar:
                        Icon(Icons.check_circle, size: 16, color: colors.done),
                    label: const Text('Done'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            if (p.doneState != null)
              Text('Done when: ${p.doneState}',
                  key: Key('look-done-state-${p.id}'), style: text.bodyMedium),
            const SizedBox(height: Space.xs),
            Wrap(
              spacing: Space.md,
              runSpacing: Space.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(p.theme?.name ?? 'No theme',
                    key: Key('look-theme-${p.id}'), style: text.bodySmall),
                if (p.rolloverCount > 0)
                  Text(
                      p.rolloverCount == 1
                          ? 'Rolled over once'
                          : 'Rolled over ${p.rolloverCount} times',
                      key: Key('look-rollover-${p.id}'),
                      style: text.bodySmall),
                OutsideFocusTag(show: p.outsideFocus),
                if (p.legacy)
                  Text('Planned before milestones',
                      key: Key('look-legacy-${p.id}'), style: text.bodySmall),
              ],
            ),
            const SizedBox(height: Space.xs),
            Text(
              p.committed == 0
                  ? 'No tasks were planned for this milestone.'
                  : '${p.done} of ${plural(p.committed, 'task')} done',
              key: Key('look-count-${p.id}'),
              style: text.bodySmall,
            ),
            if (p.committed > 0) ...[
              const SizedBox(height: Space.xs),
              LinearProgressIndicator(value: ratio, minHeight: 4),
            ],
            RescopeNudge(
                show: p.needsRescope,
                name: p.name,
                nudgeKey: Key('look-rescope-${p.id}')),
            if (!done) ..._choices(context, left, quiet),
            const SizedBox(height: Space.sm),
            // Any milestone can be archived, a finished one most of all.
            SwitchListTile(
              key: Key('archive-${p.id}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _a.archive,
              onChanged: (v) => widget.onChanged(_a.copyWith(archive: v)),
              title: const Text('Archive the project in your task app'),
              subtitle: const Text(
                  'It happens when you save. You can restore it in your task '
                  'app.'),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _choices(BuildContext context, int left, TextStyle? quiet) {
    final p = _p;
    final text = Theme.of(context).textTheme;
    if (_a.markDone) {
      return [
        const SizedBox(height: Space.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                'It will be marked done when you save. Nothing is moved or '
                'deleted.',
                key: Key('marked-done-${p.id}'),
                style: text.bodyMedium,
              ),
            ),
            TextButton(
              key: Key('unmark-done-${p.id}'),
              onPressed: () => widget.onChanged(_a.copyWith(markDone: false)),
              child: const Text('Undo'),
            ),
          ],
        ),
      ];
    }
    if (_closed) return _closedBody(context);
    final closeOpen = p.close.available && p.milestoneId != null;
    return [
      if (left > 0) ...[
        const SizedBox(height: Space.md),
        for (final t in p.leftover.take(4))
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              children: [
                const Icon(Icons.radio_button_unchecked, size: 14),
                const SizedBox(width: Space.sm),
                Expanded(child: Text(t.title, style: text.bodyMedium)),
              ],
            ),
          ),
        if (left > 4) Text('and ${left - 4} more', style: text.bodySmall),
      ],
      const SizedBox(height: Space.md),
      Text(
          left > 0
              ? 'What happens to the ${left == 1 ? 'task' : '$left tasks'} '
                  'left?'
              : 'What do you want to do with this milestone?',
          style: text.titleSmall),
      const SizedBox(height: Space.xs),
      for (final d in Decision.values)
        if (d != Decision.close || closeOpen)
          _ChoiceTile(
            key: Key('decision-${d.api}-${p.id}'),
            decision: d,
            selected: _a.decision == d,
            onTap: () => _choose(d),
          ),
      if (!closeOpen) _closeHidden(context),
      if (_a.decision == Decision.recommit)
        SwitchListTile(
          key: Key('expected-${p.id}'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: _a.expected,
          onChanged: (v) => widget.onChanged(_a.copyWith(expected: v)),
          title: const Text('This rollover is expected'),
          subtitle: const Text(
              'Switch it on when you planned this to take more than a week. '
              'An expected rollover does not trigger the re-scope hint.'),
        ),
      if (_reopened != null)
        Padding(
          padding: const EdgeInsets.only(top: Space.sm),
          child: ReopenNotice(result: _reopened!, id: p.id),
        ),
      const SizedBox(height: Space.sm),
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: Space.sm,
        children: [
          OutlinedButton(
            key: Key('mark-done-${p.id}'),
            onPressed: _markDone,
            child: const Text('Mark as done'),
          ),
          Text('Nothing is moved or deleted.', style: quiet),
        ],
      ),
    ];
  }

  /// The line that says why "Close and return tasks" is not offered.
  Widget _closeHidden(BuildContext context) {
    final p = _p;
    final text = Theme.of(context).textTheme;
    final reason = p.legacy && p.milestoneId == null
        ? 'Close is not offered: this entry is from before milestones.'
        : p.close.reasonLine;
    return Padding(
      padding: const EdgeInsets.only(top: Space.xs),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: Space.xs,
        children: [
          Text(reason,
              key: Key('close-hidden-${p.id}'),
              style: text.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          if (p.close.reason == 'no_theme')
            TextButton(
              key: Key('label-theme-${p.id}'),
              style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: Space.xs)),
              onPressed: () => openProjects(context),
              child: const Text('Label a project as theme'),
            ),
        ],
      ),
    );
  }

  List<Widget> _closedBody(BuildContext context) {
    final p = _p;
    final text = Theme.of(context).textTheme;
    final theme = p.close.themeName ?? p.theme?.name ?? 'its theme';
    final moved = _closeResult?.moved;
    return [
      const SizedBox(height: Space.md),
      Notice(
        key: Key('close-done-${p.id}'),
        icon: Icons.inventory_2_outlined,
        message: moved == null
            ? 'Closed. Its open tasks went to $theme.'
            : moved == 0
                ? 'Closed. No task had to move.'
                : 'Closed. ${plural(moved, 'task')} moved to $theme.',
        actions: [
          OutlinedButton(
            key: Key('reopen-${p.id}'),
            onPressed: _busy ? null : _reopen,
            child: const Text('Reopen'),
          ),
        ],
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: Space.xs),
          child: Text(_error!,
              key: Key('reopen-error-${p.id}'),
              style: text.bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.error)),
        ),
    ];
  }
}

/// One of the four choices: a radio mark, the name, and one sentence.
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile(
      {required this.decision,
      required this.selected,
      required this.onTap,
      super.key});

  final Decision decision;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.tefteri;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(Corner.md),
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: Space.xs),
          padding: const EdgeInsets.all(Space.md),
          decoration: BoxDecoration(
            color: selected ? scheme.surfaceContainer : null,
            borderRadius: BorderRadius.circular(Corner.md),
            border: Border.all(color: selected ? scheme.primary : colors.rule),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 20,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(decision.label, style: text.titleSmall),
                    Text(decision.sentence, style: text.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
