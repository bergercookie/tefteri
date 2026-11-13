/// The annual review screen: the Year view (spec 008).
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
import 'annual_review_controller.dart';
import 'annual_review_models.dart';
import 'annual_review_terms.dart';
import 'goal_review_card.dart';
import 'month_coverage_strip.dart';
import 'next_year_card.dart';
import 'note_editor.dart';
import 'rule_card.dart';
import 'year_split_card.dart';

/// Shows one planning year. It opens in every state of the data.
class AnnualReviewScreen extends ConsumerStatefulWidget {
  /// Creates the screen; [initialYear] defaults to this year.
  const AnnualReviewScreen({this.initialYear, super.key});

  /// Year to show first.
  final int? initialYear;

  @override
  ConsumerState<AnnualReviewScreen> createState() => _AnnualReviewScreenState();
}

class _AnnualReviewScreenState extends ConsumerState<AnnualReviewScreen> {
  late int _year;

  @override
  void initState() {
    super.initState();
    _year = widget.initialYear ?? DateTime.now().year;
  }

  @override
  Widget build(BuildContext context) {
    final review = ref.watch(annualReviewProvider(_year));
    final controller = ref.read(annualReviewProvider(_year).notifier);
    return AppShell(
      title: 'Year review',
      body: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton(
                key: const Key('today-button'),
                onPressed: () => setState(() => _year = DateTime.now().year),
                child: const Text('Today'),
              ),
              const SizedBox(width: Space.sm),
              IconButton(
                key: const Key('prev-period'),
                tooltip: 'Previous',
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setState(() => _year -= 1),
              ),
              Text('$_year', key: const Key('period-label')),
              IconButton(
                key: const Key('next-period'),
                tooltip: 'Next',
                icon: const Icon(Icons.chevron_right),
                onPressed: () => setState(() => _year += 1),
              ),
            ],
          ),
          Expanded(
            child: review.when(
              loading: () => const Loading(),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(apiErrorMessage(e), key: const Key('load-error')),
                    TextButton(
                      key: const Key('reload-button'),
                      onPressed: controller.retry,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
              data: (r) => _body(context, r, controller),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, AnnualReview review,
      AnnualReviewController controller) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final quiet = text.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    if (review.state == 'future') {
      return ListView(
        padding: const EdgeInsets.all(Space.md),
        children: [
          EmptyState(
            key: const Key('review-empty'),
            icon: Icons.calendar_month_outlined,
            message: 'This year has not started yet.',
            action: OutlinedButton(
              key: const Key('open-annual-plan'),
              onPressed: () => context.go('/annual?year=${review.year}'),
              child: const Text('Open annual planning'),
            ),
          ),
          PlanningChecklist(
              kind: ChecklistKind.year, day: DateTime(review.year), card: true),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(Space.md),
      children: [
        const TermHint(
            id: 'annual-review-terms',
            title: 'What these words mean',
            terms: annualReviewTerms,
            compact: true),
        RuleCard(state: review.state),
        const SizedBox(height: Space.sm),
        if (review.inProgress)
          _banner(context, 'In progress',
              'This year is not over. Values are shown up to now.'),
        if (review.empty?.reason == 'no_snapshots')
          _banner(context, 'No snapshots yet',
              'The year has no monthly review snapshot. Add one from a monthly review.'),
        if (review.empty?.reason == 'no_goals')
          EmptyState(
            key: const Key('review-empty'),
            message: 'No goals for this year yet.',
            action: OutlinedButton(
              key: const Key('open-annual-plan'),
              onPressed: () => context.go('/annual?year=${review.year}'),
              child: const Text('Open annual planning'),
            ),
          ),
        const SizedBox(height: Space.sm),
        Text('Months', style: text.titleMedium),
        Text(
            '${review.coverage.stored} of ${review.coverage.expected} months '
            'covered.',
            key: const Key('coverage'),
            style: quiet),
        const SizedBox(height: Space.xs),
        MonthCoverageStrip(months: review.months),
        const SizedBox(height: Space.lg),
        for (final goal in review.goals)
          GoalReviewCard(
            goal: goal,
            onSaveNote: (body) =>
                controller.putNote(goalId: goal.id, body: body),
            onDeleteNote: goal.note == null
                ? null
                : () => controller.deleteNote(goalId: goal.id),
          ),
        const SizedBox(height: Space.md),
        Text('Completed work', style: text.titleMedium),
        const SizedBox(height: Space.xs),
        YearSplitCard(split: review.split, year: review.year),
        const SizedBox(height: Space.lg),
        Text('The year in a note', style: text.titleMedium),
        NoteEditor(
          key: const Key('year-note'),
          note: review.yearNote,
          label: 'Note on the year',
          onSave: (body) => controller.putNote(body: body),
          onDelete:
              review.yearNote == null ? null : () => controller.deleteNote(),
        ),
        const SizedBox(height: Space.lg),
        NextYearCard(
            nextYear: review.nextYear, storedReview: review.storedPeriodReview),
        const SizedBox(height: Space.lg),
        PlanningChecklist(
            kind: ChecklistKind.year, day: DateTime(review.year), card: true),
      ],
    );
  }

  Widget _banner(BuildContext context, String title, String line) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: Key('review-banner-${title.toLowerCase().replaceAll(' ', '-')}'),
      margin: const EdgeInsets.only(bottom: Space.sm),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(Corner.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.titleSmall),
          Text(line,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
