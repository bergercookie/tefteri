/// Bottom sheet that shows the notes of one task.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_error.dart';
import '../../core/planning_models.dart';
import 'notes_api.dart';

/// Opens the notes of [task] in a bottom sheet.
Future<void> showTaskNotes(BuildContext context, PlanTask task) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => TaskNotesSheet(task: task),
    );

/// Lists the notes linked to [task]; a tap opens one. The user can add a
/// new note for the task or remove a link.
class TaskNotesSheet extends ConsumerStatefulWidget {
  /// Creates the sheet.
  const TaskNotesSheet({required this.task, super.key});

  /// The task.
  final PlanTask task;

  @override
  ConsumerState<TaskNotesSheet> createState() => _TaskNotesSheetState();
}

class _TaskNotesSheetState extends ConsumerState<TaskNotesSheet> {
  String? _error;

  void _open(String location) {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.go(location);
  }

  Future<void> _unlink(PlanNote n) async {
    try {
      await ref.read(notesApiProvider).unlink(widget.task.id, n.id);
    } on DioException catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
      return;
    }
    ref.invalidate(taskNotesProvider(widget.task.id));
  }

  @override
  Widget build(BuildContext context) {
    final notes = ref.watch(taskNotesProvider(widget.task.id));
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Notes for "${widget.task.title}"',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, key: const Key('task-notes-error')),
            ),
          notes.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text(apiErrorMessage(e)),
            ),
            data: (list) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (list.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No notes are linked to this task.'),
                  ),
                for (final n in list)
                  ListTile(
                    key: Key('task-note-${n.id}'),
                    leading: Icon(n.kind == 'process'
                        ? Icons.checklist
                        : Icons.description),
                    title: Text(n.title),
                    subtitle: Text(noteKindLabel(n.kind)),
                    onTap: () => _open('/notes/${n.id}'),
                    trailing: IconButton(
                      key: Key('unlink-${n.id}'),
                      tooltip: 'Remove link',
                      icon: const Icon(Icons.link_off),
                      onPressed: () => _unlink(n),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                key: const Key('task-note-new'),
                onPressed: () => _open('/notes/new?task=${widget.task.id}'),
                icon: const Icon(Icons.note_add),
                label: const Text('New note for this task'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
