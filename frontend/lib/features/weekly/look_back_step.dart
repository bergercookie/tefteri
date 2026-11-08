/// Step 1: look back at the week before. For each project the user decides
/// whether it is done, and what happens to the tasks that are left.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/theme.dart';
import 'history_view.dart';
import 'weekly_api.dart';
import 'weekly_models.dart';
import 'weekly_widgets.dart';

/// Shows the look-back form, or the history when there is nothing to review.
class LookBackStep extends ConsumerStatefulWidget {
  /// Creates the step.
  const LookBackStep({
    required this.state,
    required this.actions,
    required this.onNext,
    super.key,
  });

  /// The loaded week.
  final WeeklyState state;

  /// What the step can ask the screen to do.
  final WeeklyActions actions;

  /// Goes on to choosing projects.
  final VoidCallback onNext;

  @override
  ConsumerState<LookBackStep> createState() => _LookBackStepState();
}

class _LookBackStepState extends ConsumerState<LookBackStep> {
  final _reflection = TextEditingController();
  final Map<String, LookBackAnswer> _answers = {};
  WeeklyHistory? _saved;
  bool _saving = false;

  @override
  void dispose() {
    _reflection.dispose();
    super.dispose();
  }

  LookBackAnswer _answer(LookBackProject p) =>
      _answers[p.id] ?? LookBackAnswer(projectId: p.id);

  void _set(LookBackProject p, {bool? finished, String? leftover}) =>
      setState(() => _answers[p.id] = LookBackAnswer(
            projectId: p.id,
            finishedAnyway: finished ?? _answer(p).finishedAnyway,
            leftover: leftover ?? _answer(p).leftover,
          ));

  Future<void> _save(LookBack back) async {
    setState(() => _saving = true);
    WeeklyHistory? history;
    final ok = await widget.actions.run((api) async {
      history = await api.review(
        back.planId,
        [for (final p in back.projects) _answer(p)],
        _reflection.text,
      );
      return api.state(widget.actions.week);
    });
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) _saved = history;
    });
    ref.invalidate(weeklyHistoryProvider);
    ref.invalidate(weeklyCandidatesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final back = s.lookBack;
    if (back == null) return _nothing(context);
    if (back.reviewed || (s.plan?.retroSkipped ?? false)) {
      return _afterwards(context, back);
    }
    return _form(context, back);
  }

  Widget _nothing(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const StepHeading(
            title: 'Look back',
            subtitle: 'There is no earlier plan to look back on. '
                'Next week, you will see here how this one went.',
          ),
          const HistoryView(),
          StepFooter(nextLabel: 'Choose projects', onNext: widget.onNext),
        ],
      );

  Widget _afterwards(BuildContext context, LookBack back) {
    final skipped = !back.reviewed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StepHeading(
          title: skipped ? 'Look-back skipped' : 'Look back is done',
          subtitle: skipped
              ? 'You chose to plan without looking back at '
                  '${weekPhrase(back.weekStart)}.'
              : 'Here is how your earlier weeks went: what you committed '
                  'to, and what you finished.',
        ),
        HistoryView(history: _saved),
        StepFooter(nextLabel: 'Choose projects', onNext: widget.onNext),
      ],
    );
  }

  Widget _form(BuildContext context, LookBack back) {
    final text = Theme.of(context).textTheme;
    final committed = back.projects.length;
    final done = back.projects
        .where((p) => p.completed || _answer(p).finishedAnyway)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StepHeading(
          title: 'How did ${weekPhrase(back.weekStart)} go?',
          subtitle: 'For each project, decide if it is done and what '
              'happens to the tasks that are left.',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Wrap(
              spacing: Space.xl,
              runSpacing: Space.sm,
              children: [
                Counter(
                    key: const Key('look-committed'),
                    label: '${noun(committed, 'project')} committed',
                    value: committed),
                Counter(
                    key: const Key('look-done'),
                    label: '${noun(done, 'project')} done',
                    value: done,
                    accent: context.tefteri.done),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.sm),
        for (final p in back.projects) _project(context, p),
        const SizedBox(height: Space.md),
        Text('Anything to remember? (optional)', style: text.titleSmall),
        const SizedBox(height: Space.xs),
        TextField(
          key: const Key('reflection'),
          controller: _reflection,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
              hintText: 'What went well? What would you change?'),
        ),
        const SizedBox(height: Space.lg),
        SpreadRow(
          children: [
            TextButton(
              key: const Key('skip-look-back'),
              onPressed: _saving
                  ? null
                  : () async {
                      final ok = await widget.actions
                          .run((api) => api.skipLookBack(widget.actions.week));
                      if (ok && mounted) widget.onNext();
                    },
              child: const Text('Skip the look-back'),
            ),
            FilledButton(
              key: const Key('save-look-back'),
              onPressed: _saving ? null : () => _save(back),
              child: const Text('Save the look-back'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _project(BuildContext context, LookBackProject p) {
    final text = Theme.of(context).textTheme;
    final colors = context.tefteri;
    final answer = _answer(p);
    final left = p.leftover.length;
    final ratio = p.committed == 0 ? 0.0 : p.done / p.committed;
    return Card(
      key: Key('look-project-${p.id}'),
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(p.name, style: text.titleMedium)),
                if (p.completed)
                  Chip(
                    key: Key('look-finished-${p.id}'),
                    avatar:
                        Icon(Icons.check_circle, size: 16, color: colors.done),
                    label: const Text('All done'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            Text(
              p.committed == 0
                  ? 'No tasks were planned for this project.'
                  : '${p.done} of ${plural(p.committed, 'task')} done',
              key: Key('look-count-${p.id}'),
              style: text.bodySmall,
            ),
            if (p.committed > 0) ...[
              const SizedBox(height: Space.xs),
              LinearProgressIndicator(value: ratio, minHeight: 4),
            ],
            if (!p.completed) ...[
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
                if (left > 4)
                  Text('and ${left - 4} more', style: text.bodySmall),
                const SizedBox(height: Space.md),
                Text(
                    'What happens to the ${left == 1 ? 'task' : '$left tasks'} '
                    'left?',
                    style: text.titleSmall),
                RadioGroup<String>(
                  groupValue: answer.leftover,
                  onChanged: (v) => _set(p, leftover: v),
                  child: Column(
                    children: [
                      RadioListTile<String>(
                        key: Key('carry-${p.id}'),
                        value: 'carry',
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Carry them over'),
                        subtitle: const Text(
                            'Suggest this project again for the new week.'),
                      ),
                      RadioListTile<String>(
                        key: Key('backlog-${p.id}'),
                        value: 'backlog',
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Back to the backlog'),
                        subtitle: const Text(
                            'Remove their old day. They stay open in the project.'),
                      ),
                    ],
                  ),
                ),
              ],
              SwitchListTile(
                key: Key('finished-${p.id}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: answer.finishedAnyway,
                onChanged: (v) => _set(p, finished: v),
                title: Text(left > 0
                    ? 'Count this project as done anyway'
                    : 'Count this project as done'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
