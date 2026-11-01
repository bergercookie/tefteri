/// Documentation and process notes: a list with a kind filter.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_error.dart';
import '../../core/context_filter.dart';
import '../../core/planning_models.dart';
import '../../core/shell.dart';
import 'notes_api.dart';

/// Lists documentation and process notes; opening one shows the editor.
class NotesScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  String? _kind;

  @override
  Widget build(BuildContext context) {
    final notes = ref.watch(notesProvider(_kind));
    return AppShell(
      title: 'Notes',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<String?>(
                  key: const Key('note-kind-filter'),
                  segments: const [
                    ButtonSegment(value: null, label: Text('All')),
                    ButtonSegment(
                        value: 'custom', label: Text('Documentation')),
                    ButtonSegment(value: 'process', label: Text('Processes')),
                  ],
                  selected: {_kind},
                  onSelectionChanged: (s) => setState(() => _kind = s.first),
                ),
                FilledButton.icon(
                  key: const Key('new-note'),
                  onPressed: () => context.go(
                      '/notes/new${_kind == 'process' ? '?kind=process' : ''}'),
                  icon: const Icon(Icons.add),
                  label: const Text('New note'),
                ),
              ],
            ),
          ),
          Expanded(
            child: notes.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(apiErrorMessage(e), key: const Key('load-error')),
                    TextButton(
                      key: const Key('reload-button'),
                      onPressed: () => ref.invalidate(notesProvider(_kind)),
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
              data: (list) => list.isEmpty
                  ? const Center(child: Text('No notes yet.'))
                  : ListView(children: [for (final n in list) _tile(n)]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(PlanNote n) {
    final firstLine = n.body.split('\n').first;
    return ListTile(
      key: Key('note-${n.id}'),
      leading: Icon(n.kind == 'process' ? Icons.checklist : Icons.description),
      title: Text(n.title),
      subtitle: Text(
        '${noteKindLabel(n.kind)}${firstLine.isEmpty ? '' : ' - $firstLine'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: ContextMarker(itemContext: n.context),
      onTap: () => context.go('/notes/${n.id}'),
    );
  }
}
