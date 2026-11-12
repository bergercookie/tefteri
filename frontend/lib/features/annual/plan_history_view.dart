/// The history of one planning year (FR-019): every change in time order,
/// with the old and the new value, and Undo for each batch that is not
/// undone yet.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/planning_models.dart';
import '../../theme/theme.dart';
import 'annual_controller.dart';
import 'annual_models.dart';

/// Opens the history of [year]. [plan] names the goals and key results;
/// [onUndo] undoes a batch (null in a past year, where nothing changes).
Future<void> showPlanHistory(BuildContext context,
        {required int year,
        required AnnualPlan plan,
        Future<void> Function(String batchId)? onUndo}) =>
    showDialog<void>(
      context: context,
      builder: (_) => PlanHistoryView(year: year, plan: plan, onUndo: onUndo),
    );

/// What a change did, in words.
String changeTitle(String kind) => switch (kind) {
      'goal_created' => 'Goal added',
      'goal_edited' => 'Goal changed',
      'goal_retired' => 'Goal retired',
      'goal_restored' => 'Goal restored',
      'key_result_created' => 'Key result added',
      'key_result_edited' => 'Key result changed',
      'key_result_retired' => 'Key result retired',
      'key_result_restored' => 'Key result restored',
      'link_added' => 'Theme linked',
      'link_ended' => 'Theme link ended',
      'migrated' => 'Moved from the old goals',
      'undo' => 'Undone',
      _ => kind.replaceAll('_', ' '),
    };

const _undoableKinds = {
  'goal_retired',
  'key_result_retired',
  'link_added',
  'link_ended',
};

String _field(String f) => switch (f) {
      'update_source' => 'update source',
      'title' => 'text',
      _ => f.replaceAll('_', ' '),
    };

/// The history view.
class PlanHistoryView extends ConsumerStatefulWidget {
  /// Creates the view.
  const PlanHistoryView(
      {required this.year, required this.plan, this.onUndo, super.key});

  /// The planning year.
  final int year;

  /// The plan, for names.
  final AnnualPlan plan;

  /// Undoes a batch; null hides Undo.
  final Future<void> Function(String batchId)? onUndo;

  @override
  ConsumerState<PlanHistoryView> createState() => _PlanHistoryViewState();
}

class _PlanHistoryViewState extends ConsumerState<PlanHistoryView> {
  String? _error;
  bool _busy = false;

  Future<void> _undo(String batch) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onUndo!(batch);
      ref.invalidate(planHistoryProvider(widget.year));
    } catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _subject(PlanChange c) {
    final kr =
        c.keyResultId == null ? null : widget.plan.keyResult(c.keyResultId!);
    if (kr != null) return kr.metric;
    final goal = c.goalId == null ? null : widget.plan.goal(c.goalId!);
    return goal?.title ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(planHistoryProvider(widget.year));
    return AlertDialog(
      key: const Key('plan-history'),
      title: Text('History of ${widget.year}'),
      content: SizedBox(
        width: 560,
        child: history.when(
          loading: () => const SizedBox(height: 120, child: Loading()),
          error: (e, _) => EmptyState(
            message: apiErrorMessage(e),
            action: TextButton(
              onPressed: () => ref.invalidate(planHistoryProvider(widget.year)),
              child: const Text('Try again'),
            ),
          ),
          data: (changes) => changes.isEmpty
              ? const EmptyState(
                  messageKey: Key('history-empty'),
                  message: 'No changes in this year yet.',
                  icon: Icons.history)
              : SingleChildScrollView(child: _list(changes)),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _list(List<PlanChange> changes) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final undoShown = <String>{};
    // Undo sits on the last line of each batch that can still be undone.
    final lastOfBatch = <String, String>{};
    // Only retires and link changes can be undone (`POST /annual/undo`).
    final undoable = <String>{};
    for (final c in changes) {
      lastOfBatch[c.batchId] = c.id;
      if (_undoableKinds.contains(c.kind)) undoable.add(c.batchId);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in changes)
          Container(
            key: Key('change-${c.id}'),
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            decoration: BoxDecoration(
                border:
                    Border(bottom: BorderSide(color: context.tefteri.rule))),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 96,
                  child: Text(dateKey(c.at.toLocal()), style: text.bodySmall),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          [
                            changeTitle(c.kind),
                            if (_subject(c).isNotEmpty) '"${_subject(c)}"',
                          ].join(': '),
                          style: text.bodyMedium),
                      if (c.field != null ||
                          c.oldValue != null ||
                          c.newValue != null)
                        Text(
                            '${c.field == null ? '' : '${_field(c.field!)}: '}'
                            '${c.oldValue ?? '–'} → ${c.newValue ?? '–'}',
                            style: text.bodySmall),
                      if (c.reason != null && c.reason!.isNotEmpty)
                        Text('Reason: ${c.reason}', style: text.bodySmall),
                      if (c.undone)
                        Text('Undone',
                            style: text.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                if (widget.onUndo != null &&
                    !c.undone &&
                    c.source == 'user' &&
                    undoable.contains(c.batchId) &&
                    lastOfBatch[c.batchId] == c.id &&
                    undoShown.add(c.batchId))
                  TextButton(
                    key: Key('undo-batch-${c.batchId}'),
                    onPressed: _busy ? null : () => _undo(c.batchId),
                    child: const Text('Undo'),
                  ),
              ],
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: Text(_error!, style: TextStyle(color: scheme.error)),
          ),
      ],
    );
  }
}
