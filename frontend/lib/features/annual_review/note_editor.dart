/// An inline note editor with save on submit, delete and undo.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/api_error.dart';
import '../../theme/theme.dart';
import 'annual_review_models.dart';

/// Edits the note of the year or of one goal.
class NoteEditor extends StatefulWidget {
  /// Creates the editor.
  const NoteEditor({
    required this.onSave,
    this.onDelete,
    this.note,
    this.label = 'Note',
    super.key,
  });

  /// Stores [body]. Returns the stored note.
  final Future<ReviewNote> Function(String body) onSave;

  /// Deletes the note and returns the text that was lost.
  final Future<ReviewNote> Function()? onDelete;

  /// The current note, or null.
  final ReviewNote? note;

  /// Hint under the field.
  final String label;

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late final TextEditingController _text =
      TextEditingController(text: widget.note?.body ?? '');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final body = _text.text.trim();
    if (body.isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final note = await widget.onSave(body);
      _text.text = note.body;
    } on DioException catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final onDelete = widget.onDelete;
    if (onDelete == null) return;
    try {
      final lost = await onDelete();
      if (!mounted) return;
      _text.text = '';
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(SnackBar(
        content: Text('Note deleted: ${lost.body}'),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await widget.onSave(lost.body);
          },
        ),
      ));
    } on DioException catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: Space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('note-field'),
                  controller: _text,
                  maxLines: null,
                  minLines: 1,
                  decoration: InputDecoration(
                    labelText: widget.label,
                    hintText: 'Write a short note.',
                  ),
                  onSubmitted: (_) => _save(),
                ),
              ),
              const SizedBox(width: Space.sm),
              IconButton(
                key: const Key('note-save'),
                tooltip: 'Save note',
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check),
              ),
              if (widget.onDelete != null)
                IconButton(
                  key: const Key('note-delete'),
                  tooltip: 'Delete note',
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
          if (widget.note != null)
            Text('Saved ${_date(widget.note!.updatedAt)}',
                style:
                    text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          if (_error != null)
            Text(_error!,
                key: const Key('note-error'),
                style: text.bodySmall?.copyWith(color: scheme.error)),
        ],
      ),
    );
  }
}

String _date(DateTime? d) {
  if (d == null) return '';
  final l = d.toLocal();
  return '${l.year}-${l.month.toString().padLeft(2, '0')}-'
      '${l.day.toString().padLeft(2, '0')}';
}
