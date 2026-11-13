/// One goal of the annual review, with its key results and its note.
library;

import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import 'annual_review_models.dart';
import 'key_result_row.dart';
import 'note_editor.dart';

/// Shows one goal.
class GoalReviewCard extends StatelessWidget {
  /// Creates the card.
  const GoalReviewCard({
    required this.goal,
    required this.onSaveNote,
    this.onDeleteNote,
    super.key,
  });

  /// The goal.
  final ReviewGoal goal;

  /// Saves the goal note.
  final Future<ReviewNote> Function(String body) onSaveNote;

  /// Deletes the goal note.
  final Future<ReviewNote> Function()? onDeleteNote;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final quiet = text.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final counts = goal.counts;
    final summary = [
      if (counts['hit'] != null) '${counts['hit']} hit',
      if (counts['missed'] != null) '${counts['missed']} missed',
      if (counts['no_value'] != null && (counts['no_value'] as num) > 0)
        '${counts['no_value']} without a value',
    ].join(', ');
    return Container(
      key: Key('goal-${goal.id}'),
      margin: const EdgeInsets.only(bottom: Space.md),
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: context.tefteri.rule),
        borderRadius: BorderRadius.circular(Corner.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(goal.title, style: text.titleMedium)),
              if (goal.status == 'retired')
                Text('Retired ${_day(goal.retiredAt)}', style: quiet),
            ],
          ),
          if (summary.isNotEmpty) Text(summary, style: quiet),
          if (goal.status == 'retired' && goal.retiredReason != null)
            Text(goal.retiredReason!, style: quiet),
          if (goal.keyResults.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                        'No key result yet. A goal shows its result '
                        'through its key results.',
                        style: quiet),
                  ),
                  TextButton(
                    key: const Key('open-annual-plan'),
                    onPressed: () {},
                    child: const Text('Open annual planning'),
                  ),
                ],
              ),
            ),
          for (final k in goal.keyResults) KeyResultRow(keyResult: k),
          if (goal.note != null || goal.keyResults.isNotEmpty)
            NoteEditor(
              key: Key('goal-note-${goal.id}'),
              note: goal.note,
              label: 'Note on this goal',
              onSave: onSaveNote,
              onDelete: onDeleteNote,
            ),
        ],
      ),
    );
  }
}

String _day(DateTime? d) => d == null
    ? ''
    : '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
