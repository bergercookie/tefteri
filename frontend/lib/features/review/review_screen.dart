/// Review of one plan: planned versus completed, carried-over items and the
/// retrospective.
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

/// Shows the stored review of [planId]; the user can compute it again and
/// save a retrospective, which goes to the note app.
class ReviewScreen extends ConsumerStatefulWidget {
  /// Creates the screen for the plan [planId].
  const ReviewScreen({required this.planId, super.key});

  /// Plan to review.
  final String planId;

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  final _retro = TextEditingController();
  String? _error;
  String? _loadedFor;
  bool _saving = false;

  @override
  void dispose() {
    _retro.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      await ref.read(reviewApiProvider).review(widget.planId, refresh: true);
    } on DioException catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
      return;
    }
    if (!mounted) return;
    setState(() => _error = null);
    ref.invalidate(planReviewProvider(widget.planId));
    ref.invalidate(planHistoryProvider);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(reviewApiProvider)
          .saveRetrospective(widget.planId, _retro.text);
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = apiErrorMessage(e);
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Retrospective saved to your notes app.')));
    ref.invalidate(planReviewProvider(widget.planId));
    ref.invalidate(planHistoryProvider);
  }

  @override
  Widget build(BuildContext context) {
    final review = ref.watch(planReviewProvider(widget.planId));
    return AppShell(
      title: 'Review',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null)
            ErrorBanner(
                message: _error!,
                onDismiss: () => setState(() => _error = null)),
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
                      onPressed: () =>
                          ref.invalidate(planReviewProvider(widget.planId)),
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
              data: _body,
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(PlanReview r) {
    // Fill the editor once per loaded retrospective, not on every rebuild.
    final key = '${r.planId}/${r.retrospective?.id}';
    if (_loadedFor != key) {
      _loadedFor = key;
      _retro.text = r.retrospective?.body ?? '';
    }
    final text = Theme.of(context).textTheme;
    final carried = r.items.where((i) => !i.completed).toList();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            IconButton(
              key: const Key('back-to-history'),
              tooltip: 'All plans',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/review'),
            ),
            Expanded(
              child: Text(r.planTitle,
                  key: const Key('review-title'), style: text.titleLarge),
            ),
            TextButton.icon(
              key: const Key('review-refresh'),
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Update review'),
            ),
          ],
        ),
        Text(
          '${periodLabel(r.periodType, r.periodStart)}'
          '${r.periodEnded ? '' : ' (in progress)'}'
          ' - review from ${dateKey(r.generatedAt.toLocal())}',
          style: text.bodySmall,
        ),
        const SizedBox(height: 12),
        Text('${r.completedCount} of ${r.plannedCount} ${r.goalsWord} done',
            key: const Key('review-counts'), style: text.titleMedium),
        const SizedBox(height: 4),
        LinearProgressIndicator(
            key: const Key('review-progress'), value: r.ratio),
        const SizedBox(height: 16),
        Text('Planned', style: text.titleSmall),
        if (r.items.isEmpty) const Text('Nothing was planned for this period.'),
        for (final i in r.items) _item(i, r),
        const SizedBox(height: 16),
        Text('Carried over (${carried.length})',
            key: const Key('carried-heading'), style: text.titleSmall),
        if (carried.isEmpty) const Text('Nothing to carry over.'),
        for (final i in carried)
          ListTile(
            key: Key('carried-${i.id}'),
            dense: true,
            leading: const Icon(Icons.redo),
            title: Text(i.title),
            subtitle: Text(r.itemWord(i.type)),
          ),
        const SizedBox(height: 16),
        Text('Retrospective', style: text.titleSmall),
        const SizedBox(height: 4),
        TextField(
          key: const Key('retro-field'),
          controller: _retro,
          minLines: 4,
          maxLines: 12,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'What went well? What do you want to change?',
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            key: const Key('retro-save'),
            onPressed: _saving ? null : _save,
            child: const Text('Save to notes app'),
          ),
        ),
        if (r.retrospective != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Saved as the note "${r.retrospective!.title}".',
                key: const Key('retro-saved'), style: text.bodySmall),
          ),
      ],
    );
  }

  Widget _item(ReviewItem i, PlanReview r) => ListTile(
        key: Key('item-${i.id}'),
        dense: true,
        leading: Icon(
          i.completed ? Icons.check_circle : Icons.radio_button_unchecked,
          color: i.completed ? context.tefteri.done : null,
          semanticLabel: i.completed ? 'Done' : 'Not done',
        ),
        title: Text(i.title),
        subtitle: Text(r.itemWord(i.type)),
      );
}
