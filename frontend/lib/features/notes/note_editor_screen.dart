/// Editor for one documentation or process note.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_error.dart';
import '../../core/shell.dart';
import 'notes_api.dart';

/// Edits the note [noteId], or creates a new note when [noteId] is null.
///
/// A new note can be linked to the task [taskId] and starts with [kind].
/// Saving writes to the note app first; nothing is kept when that fails.
class NoteEditorScreen extends ConsumerStatefulWidget {
  /// Creates the editor.
  const NoteEditorScreen(
      {this.noteId, this.taskId, this.kind = 'custom', super.key});

  /// Note to edit; null for a new note.
  final String? noteId;

  /// Task to link a new note to.
  final String? taskId;

  /// Kind of a new note: `custom` (documentation) or `process`.
  final String kind;

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  late String _kind = widget.kind;
  String? _loadedId;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Write a title.');
      return;
    }
    setState(() => _busy = true);
    final api = ref.read(notesApiProvider);
    try {
      if (widget.noteId == null) {
        final created = await api.create(
          title: title,
          body: _body.text,
          kind: _kind,
          taskIds: [if (widget.taskId != null) widget.taskId!],
        );
        if (!mounted) return;
        ref.invalidate(notesProvider);
        if (widget.taskId != null) {
          ref.invalidate(taskNotesProvider(widget.taskId!));
        }
        context.go('/notes/${created.note.id}');
        return;
      }
      await api.update(widget.noteId!, title: title, body: _body.text);
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = apiErrorMessage(e);
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = null;
    });
    ref.invalidate(notesProvider);
    ref.invalidate(noteDetailProvider(widget.noteId!));
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Note saved to your notes app.')));
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this note?'),
        content: const Text('The note is deleted in your notes app too. '
            'Linked tasks stay.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('note-delete-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(notesApiProvider).delete(widget.noteId!);
    } on DioException catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
      return;
    }
    if (!mounted) return;
    ref.invalidate(notesProvider);
    context.go('/notes');
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.noteId;
    if (id == null) return _shell(_form(taskIds: const []));
    final detail = ref.watch(noteDetailProvider(id));
    return _shell(detail.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(apiErrorMessage(e), key: const Key('load-error')),
            TextButton(
              key: const Key('reload-button'),
              onPressed: () => ref.invalidate(noteDetailProvider(id)),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
      data: (d) {
        // Fill the fields once per note, so typing is not overwritten.
        if (_loadedId != d.note.id) {
          _loadedId = d.note.id;
          _title.text = d.note.title;
          _body.text = d.note.body;
          _kind = d.note.kind;
        }
        return _form(taskIds: d.taskIds);
      },
    ));
  }

  Widget _shell(Widget body) => AppShell(
        title: widget.noteId == null ? 'New note' : 'Note',
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null)
              ErrorBanner(
                  message: _error!,
                  onDismiss: () => setState(() => _error = null)),
            Expanded(child: body),
          ],
        ),
      );

  Widget _form({required List<String> taskIds}) {
    final isNew = widget.noteId == null;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            IconButton(
              key: const Key('back-to-notes'),
              tooltip: 'All notes',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/notes'),
            ),
            if (isNew)
              SegmentedButton<String>(
                key: const Key('note-kind'),
                segments: const [
                  ButtonSegment(value: 'custom', label: Text('Documentation')),
                  ButtonSegment(value: 'process', label: Text('Process')),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() => _kind = s.first),
              )
            else
              Chip(label: Text(noteKindLabel(_kind))),
            const Spacer(),
            if (!isNew)
              IconButton(
                key: const Key('note-delete'),
                tooltip: 'Delete note',
                icon: const Icon(Icons.delete_outline),
                onPressed: _delete,
              ),
          ],
        ),
        TextField(
          key: const Key('note-title'),
          controller: _title,
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('note-body'),
          controller: _body,
          minLines: 8,
          maxLines: 24,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: _kind == 'process'
                ? 'One step on each line, for example:\n1. Do this\n2. Then this'
                : 'Write the documentation here.',
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            FilledButton(
              key: const Key('note-save'),
              onPressed: _busy ? null : _save,
              child: const Text('Save'),
            ),
            const SizedBox(width: 12),
            if (widget.taskId != null && isNew)
              const Text('This note is linked to the task.'),
            if (!isNew)
              Text(
                taskIds.isEmpty
                    ? 'Not linked to a task.'
                    : 'Linked to ${taskIds.length} task(s).',
                key: const Key('note-links'),
              ),
          ],
        ),
      ],
    );
  }
}
