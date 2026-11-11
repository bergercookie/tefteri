/// Step 1: the weekly review. The summary of the week comes first, then one
/// card per milestone where the user decides what happens to it.
library;

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/theme.dart';
import '../projects/term_hint.dart';
import 'decision_card.dart';
import 'history_view.dart';
import 'rescope_nudge.dart';
import 'review_summary.dart';
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

  /// Goes on to choosing milestones.
  final VoidCallback onNext;

  @override
  ConsumerState<LookBackStep> createState() => _LookBackStepState();
}

class _LookBackStepState extends ConsumerState<LookBackStep> {
  final _reflection = TextEditingController();
  final Map<String, LookBackAnswer> _answers = {};
  ReviewResult? _saved;
  bool _saving = false;

  @override
  void dispose() {
    _reflection.dispose();
    super.dispose();
  }

  LookBackAnswer _answer(LookBackProject p) =>
      _answers[p.id] ?? LookBackAnswer(projectId: p.id);

  /// What is sent for [p]: a milestone that was closed here has the decision
  /// close, whatever the card says.
  LookBackAnswer _toSend(LookBackProject p) =>
      p.closed ? _answer(p).withDecision(Decision.close) : _answer(p);

  Future<void> _save(LookBack back) async {
    setState(() => _saving = true);
    ReviewResult? result;
    final ok = await widget.actions.run((api) async {
      result = await api.review(
        back.planId,
        [for (final p in back.projects) _toSend(p)],
        _reflection.text,
      );
      return api.state(widget.actions.week);
    });
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) _saved = result;
    });
    ref.invalidate(weeklyHistoryProvider);
    ref.invalidate(weeklyCandidatesProvider);
    ref.invalidate(weeklyThemesProvider);
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
          StepFooter(nextLabel: 'Choose milestones', onNext: widget.onNext),
        ],
      );

  Widget _afterwards(BuildContext context, LookBack back) {
    final skipped = !back.reviewed;
    final saved = _saved;
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
        if (saved != null) _result(context, saved),
        HistoryView(history: saved?.history),
        StepFooter(nextLabel: 'Choose milestones', onNext: widget.onNext),
      ],
    );
  }

  /// What saving the review changed, and the milestones that need a closer
  /// look. It does not block anything.
  Widget _result(BuildContext context, ReviewResult r) {
    if (r.notices.isEmpty && r.nudges.isEmpty) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Card(
        key: const Key('review-result'),
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final n in r.notices)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.xs),
                  child: Text(n,
                      key: const Key('review-notice'), style: text.bodyMedium),
                ),
              if (r.nudges.isNotEmpty) ...[
                Text('Worth a closer look', style: text.titleSmall),
                for (final n in r.nudges)
                  RescopeNudge(
                      show: true,
                      name: n.name,
                      nudgeKey: Key('result-nudge-${n.milestoneId}')),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _form(BuildContext context, LookBack back) {
    final text = Theme.of(context).textTheme;
    final open = [
      for (final p in back.projects)
        if (needsDecision(p, _answer(p))) p,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StepHeading(
          title: 'How did ${weekPhrase(back.weekStart)} go?',
          subtitle: 'See how the week went, then decide what happens to each '
              'milestone that is not finished.',
        ),
        ReviewSummaryCard(summary: back.summary),
        const SizedBox(height: Space.sm),
        const TermHint(
          id: 'weekly-review',
          title: 'Words used here',
          compactTitle: 'What do rollover and decide later mean?',
          compact: true,
          terms: weeklyReviewTerms,
        ),
        if (back.projects.isEmpty)
          const EmptyState(
            icon: Icons.folder_open_outlined,
            messageKey: Key('look-no-milestones'),
            message: 'No milestone was committed that week.',
          ),
        for (final p in back.projects)
          DecisionCard(
            key: ValueKey('decision-card-${p.id}'),
            project: p,
            answer: _answer(p),
            actions: widget.actions,
            onChanged: (a) => setState(() => _answers[p.id] = a),
          ),
        if (open.isNotEmpty) _undecided(context, open),
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

  /// Names the milestones without a choice. Saving never waits for them: they
  /// stay as they are ("decide later").
  Widget _undecided(BuildContext context, List<LookBackProject> open) {
    return Padding(
      padding: const EdgeInsets.only(top: Space.sm),
      child: Notice(
        key: const Key('undecided'),
        icon: Icons.help_outline,
        message: open.length == 1
            ? '"${open.first.name}" has no choice yet. You can save anyway: '
                'it stays as it is and the picker reminds you next time.'
            : '${open.length} milestones have no choice yet: '
                '${[for (final p in open) '"${p.name}"'].join(', ')}. You can '
                'save anyway: they stay as they are and the picker reminds '
                'you next time.',
        actions: [
          OutlinedButton(
            key: const Key('decide-later-all'),
            onPressed: () => setState(() {
              for (final p in open) {
                _answers[p.id] = _answer(p).withDecision(Decision.decideLater);
              }
            }),
            child: const Text('Decide later for all of these'),
          ),
        ],
      ),
    );
  }
}
