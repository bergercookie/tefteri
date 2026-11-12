/// Monthly review: read results, update values and store a versioned snapshot.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_error.dart';
import '../../core/shell.dart';
import '../../theme/theme.dart';
import '../projects/term_hint.dart';
import 'month_controller.dart';
import 'month_models.dart';
import 'review_categories_section.dart';
import 'review_key_results_section.dart';
import 'review_results_section.dart';
import 'review_versions_sheet.dart';
import 'theme_decision_card.dart';

/// Review of [month] (`YYYY-MM`).
class MonthReviewScreen extends ConsumerWidget {
  /// Creates the review screen.
  const MonthReviewScreen({required this.month, super.key});

  /// Month key, `YYYY-MM`.
  final String month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewState = ref.watch(monthReviewProvider(month));
    return AppShell(
      title: 'Monthly review',
      body: reviewState.when(
        loading: () => const Loading(),
        error: (error, _) => Center(
          child: EmptyState(
            message: apiErrorMessage(error),
            action: TextButton(
              onPressed: () =>
                  ref.read(monthReviewProvider(month).notifier).load(),
              child: const Text('Try again'),
            ),
          ),
        ),
        data: (review) => _ReviewContent(month: month, review: review),
      ),
    );
  }
}

class _ReviewContent extends ConsumerStatefulWidget {
  const _ReviewContent({required this.month, required this.review});

  final String month;
  final MonthReview review;

  @override
  ConsumerState<_ReviewContent> createState() => _ReviewContentState();
}

class _ReviewContentState extends ConsumerState<_ReviewContent> {
  String? _error;
  bool _saving = false;

  Future<void> _finish() async {
    final controller = ref.read(monthReviewProvider(widget.month).notifier);
    if (widget.review.stored) {
      final confirmVersion = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Save a new review version?'),
          content: const Text(
            'Saving creates a new version. The old version stays in the history.',
            key: Key('new-version-notice'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              key: const Key('confirm-new-version'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (confirmVersion != true || !mounted) return;
    }
    final themes = widget.review.snapshot['themes'] as List? ?? const [];
    final storedDecisions =
        widget.review.snapshot['decisions'] as List? ?? const [];
    final storedById = <String, Map<String, dynamic>>{
      for (final item in storedDecisions)
        if (item is Map)
          '${item['project_id']}': Map<String, dynamic>.from(item),
    };
    final neededLater = <String>[];
    for (final item in themes) {
      if (item is! Map) continue;
      final id = '${item['project_id']}';
      final prior = controller.decisions[id] ?? storedById[id];
      if (prior == null) {
        neededLater.add('${item['name'] ?? 'A theme'}');
        controller.setDecision(id, 'later');
      } else if (!controller.decisions.containsKey(id)) {
        controller.setDecision(
          id,
          '${prior['decision'] ?? 'later'}',
          replacementProjectId: prior['replacement_project_id'] as String?,
        );
      }
    }

    if (neededLater.isNotEmpty) {
      final continueLater = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Decide later?'),
          content: Text(
            '${neededLater.join(', ')} will be saved as “decide later”. '
            'You can finish the review now and change the decision later.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Go back')),
            FilledButton(
                key: const Key('finish-with-later'),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Finish and decide later')),
          ],
        ),
      );
      if (continueLater != true || !mounted) return;
    }

    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      final preview =
          await controller.preview(confirmNewVersion: widget.review.stored);
      if (!mounted) return;
      final version = preview['will_create_version'];
      final effects = preview['effects'] as List? ?? const [];
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          key: const Key('review-save-effect'),
          title: const Text('Finish this review?'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.review.stored)
                    const Text(
                      'Saving creates a new version. The old version stays in the history.',
                      key: Key('new-version-effect-note'),
                    ),
                  if (version is num)
                    Text('This will store version ${version.toInt()}.'),
                  for (final item in effects)
                    if (item is Map) Text('${item['message'] ?? ''}'),
                  const SizedBox(height: Space.sm),
                  const Text(
                    'Your snapshot keeps these names and numbers. It does not change by itself.',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep editing')),
            FilledButton(
                key: const Key('confirm-save-review'),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Save review')),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
      await controller.save(confirmNewVersion: widget.review.stored);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Review snapshot saved.')),
      );
    } catch (error) {
      if (mounted) setState(() => _error = apiErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _decisionFor(String projectId) {
    final draft = ref
        .read(monthReviewProvider(widget.month).notifier)
        .decisions[projectId];
    if (draft != null) return '${draft['decision']}';
    for (final raw
        in widget.review.snapshot['decisions'] as List? ?? const []) {
      if (raw is Map && '${raw['project_id']}' == projectId) {
        return '${raw['decision'] ?? 'later'}';
      }
    }
    return 'later';
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(monthReviewProvider(widget.month).notifier);
    final snapshot = widget.review.snapshot;
    final themes = snapshot['themes'] as List? ?? const [];
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 860;
      return SingleChildScrollView(
        padding: EdgeInsets.all(wide ? Space.xl : Space.lg),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Back to month',
                      key: const Key('back-to-month'),
                      onPressed: () =>
                          context.go('/month?date=${widget.month}-01'),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    Expanded(
                      child: Text(
                        '${widget.month} · ${widget.review.draft ? 'Draft review' : 'Review snapshot v${widget.review.version}'}',
                        key: const Key('review-period-label'),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    if (widget.review.stored)
                      TextButton(
                        key: const Key('review-versions'),
                        onPressed: () => showReviewVersionsSheet(
                          context,
                          month: widget.month,
                          review: widget.review,
                        ),
                        child: const Text('Versions'),
                      ),
                  ],
                ),
                const SizedBox(height: Space.md),
                const TermHint(
                  id: 'monthly-review-terms',
                  title: 'Monthly review',
                  terms: monthlyReviewTerms,
                ),
                if (widget.review.draft)
                  Container(
                    key: const Key('draft-label'),
                    margin: const EdgeInsets.only(bottom: Space.lg),
                    padding: const EdgeInsets.all(Space.md),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(Corner.md),
                      border: Border.all(color: context.tefteri.rule),
                    ),
                    child: const Text(
                      'Draft · this live review is not saved until you finish.',
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.md),
                    child: Text(_error!,
                        key: const Key('review-save-error'),
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ),
                ReviewResultsSection(snapshot: snapshot),
                const SizedBox(height: Space.xl),
                ReviewKeyResultsSection(
                  snapshot: snapshot,
                  values: controller.values,
                  onValueChanged: controller.setValue,
                ),
                const SizedBox(height: Space.xl),
                ReviewCategoriesSection(
                  snapshot: snapshot,
                  trend: widget.review.trend,
                  categoriesNote: widget.review.categoriesNote,
                ),
                const SizedBox(height: Space.xl),
                Text('Decide what happens next',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: Space.xs),
                Text(
                  'Carry, drop, replace or decide later. Replace is a '
                  'month-end decision; swap changes the focus during the month.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                for (final raw in themes)
                  if (raw is Map)
                    Builder(builder: (context) {
                      final theme = Map<String, dynamic>.from(raw);
                      final id = '${theme['project_id']}';
                      return ThemeDecisionCard(
                        key: ValueKey('decision-$id'),
                        month: widget.month,
                        theme: theme,
                        initialDecision: _decisionFor(id),
                        onChanged: (decision, {String? replacementProjectId}) =>
                            controller.setDecision(
                          id,
                          decision,
                          replacementProjectId: replacementProjectId,
                        ),
                      );
                    }),
                if (themes.isEmpty)
                  EmptyState(
                    message: 'No theme decisions are needed.',
                    action: TextButton(
                      onPressed: () =>
                          context.go('/month?date=${widget.month}-01'),
                      child: const Text('Return to monthly planning'),
                    ),
                  ),
                const SizedBox(height: Space.xl),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    key: const Key('save-month-review'),
                    onPressed: _saving ? null : _finish,
                    child: Text(_saving
                        ? 'Saving…'
                        : widget.review.stored
                            ? 'Save a new version'
                            : 'Finish review'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}
