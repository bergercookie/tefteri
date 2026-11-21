/// One task of the week that is not done yet.
library;

import 'package:flutter/material.dart';

import '../../core/planning_models.dart';
import '../../core/project_chip.dart';
import '../../theme/theme.dart';
import 'statistics_models.dart';
import 'task_status_button.dart';

/// One task that is not done: its TODO button, title, project and due day.
class OpenTaskRow extends StatelessWidget {
  /// Creates the row; [onComplete] runs when the user taps TODO.
  const OpenTaskRow(
      {required this.task, required this.onComplete, this.onOpen, super.key});

  /// The task.
  final OpenTask task;

  /// Called when the user taps the TODO button.
  final VoidCallback onComplete;

  /// Called when the user taps the title: it opens the task to edit it. When
  /// null the title is plain text.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final due = task.dueAt?.toLocal();
    return Padding(
      key: Key('open-task-${task.id}'),
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TaskStatusButton(
            key: Key('open-complete-${task.id}'),
            done: false,
            category: task.category,
            onPressed: onComplete,
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  key: Key('open-edit-${task.id}'),
                  onTap: onOpen,
                  borderRadius: BorderRadius.circular(Corner.sm),
                  child: Text(task.title, style: text.bodyMedium),
                ),
                if (task.project != null && task.project!.isNotEmpty)
                  ProjectChip(
                      name: task.project!,
                      color: task.projectColor,
                      work: task.work),
              ],
            ),
          ),
          if (due != null) ...[
            const SizedBox(width: Space.sm),
            Text(dateKey(due),
                style:
                    text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}
