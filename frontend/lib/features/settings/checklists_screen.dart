/// Settings page where the user writes their planning checklists.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/planning_api.dart';
import '../../core/planning_models.dart';
import '../../core/shell.dart';
import '../../theme/theme.dart';
import '../checklists/checklist_text.dart';
import 'planner_settings_card.dart' show userSettingsProvider;

/// What to suggest when a list is empty. The user can change every line.
const Map<ChecklistKind, List<String>> checklistExamples = {
  ChecklistKind.week: [
    'Look back at last week',
    'Check the calendar for the week',
    'Clear the inbox',
    'Pick the most important tasks',
    'Block time for focused work',
  ],
  ChecklistKind.month: [
    'Look back at the month',
    'Update the key results',
    'Check the budget',
    'Choose the themes for next month',
  ],
  ChecklistKind.year: [
    'Look back at the year',
    'Review the goals of the year',
    'Set the goals for next year',
    'Back up the important files',
  ],
};

/// Widest the form gets, so that the lines stay readable.
const double checklistsFormWidth = 640;

/// One box for each kind of planning, one item per line.
class ChecklistsScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const ChecklistsScreen({super.key});

  @override
  ConsumerState<ChecklistsScreen> createState() => _ChecklistsScreenState();
}

class _ChecklistsScreenState extends ConsumerState<ChecklistsScreen> {
  final _boxes = {
    for (final k in ChecklistKind.values) k: TextEditingController(),
  };
  final _sources = {
    for (final k in ChecklistKind.values) k: TextEditingController(),
  };

  /// The lists as the server has them; the boxes are measured against these.
  Map<ChecklistKind, List<String>>? _saved;

  /// The note paths as the server has them.
  Map<ChecklistKind, String>? _savedSources;
  bool _busy = false;
  bool _justSaved = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _boxes.values) {
      c.dispose();
    }
    for (final c in _sources.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> _items(ChecklistKind k) => parseChecklistText(_boxes[k]!.text);

  String _source(ChecklistKind k) => _sources[k]!.text.trim();

  bool _changed(ChecklistKind k) =>
      _saved != null && !_same(_items(k), _saved![k] ?? const []);

  bool _sourceChanged(ChecklistKind k) =>
      _savedSources != null && _source(k) != (_savedSources![k] ?? '');

  static bool _same(List<String> a, List<String> b) =>
      a.length == b.length &&
      [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((x) => x);

  bool get _anyChanged =>
      ChecklistKind.values.any((k) => _changed(k) || _sourceChanged(k));

  bool get _anyProblem => ChecklistKind.values
      .any((k) => _source(k).isEmpty && checklistProblem(_items(k)) != null);

  /// Fills the boxes from the server the first time, and after a save.
  void _load(UserSettings s) {
    _saved = {for (final k in ChecklistKind.values) k: s.itemsOf(k)};
    _savedSources = {
      for (final k in ChecklistKind.values) k: s.sourceOf(k).trim(),
    };
    for (final k in ChecklistKind.values) {
      _boxes[k]!.text = checklistText(_saved![k]!);
      _sources[k]!.text = _savedSources![k]!;
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
      _justSaved = false;
    });
    try {
      // Only what changed is sent: a list or path that someone else changed on
      // another device is not overwritten by an old copy.
      final lists = <ChecklistKind, List<String>>{
        for (final k in ChecklistKind.values)
          if (_source(k).isEmpty && _changed(k)) k: _items(k),
      };
      final sources = <ChecklistKind, String>{
        for (final k in ChecklistKind.values)
          if (_sourceChanged(k)) k: _source(k),
      };
      final saved = await ref.read(planningApiProvider).updateSettings(
            checklists: lists.isEmpty ? null : lists,
            checklistSources: sources.isEmpty ? null : sources,
          );
      ref.invalidate(userSettingsProvider);
      if (mounted) {
        setState(() {
          _load(saved);
          _justSaved = true;
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(userSettingsProvider);
    if (_saved == null && settings.hasValue) _load(settings.requireValue);
    return AppShell(
      title: 'Checklists',
      backTo: '/settings',
      body: settings.when(
        loading: () => const Loading(),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(apiErrorMessage(e), key: const Key('checklists-load-error')),
              TextButton(
                key: const Key('checklists-retry'),
                onPressed: () => ref.invalidate(userSettingsProvider),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
        data: (_) => _form(context),
      ),
    );
  }

  Widget _form(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Space.lg),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: checklistsFormWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'A checklist is what you want to go through when you plan. '
                'Write one item on each line. The weekly list shows next to '
                'the weekly planning. The monthly and annual lists show on '
                'the Month and Year pages. You tick the items there, and the '
                'list starts clean each week, month or year. You can also '
                'read a checklist from your notes app: give its path below, '
                'and the list is read-only and refreshed from the note each '
                'time it is shown.',
                key: const Key('checklists-intro'),
                style: text.bodyMedium,
              ),
              for (final k in ChecklistKind.values) ...[
                const SizedBox(height: Space.xl),
                _section(context, k),
              ],
              const SizedBox(height: Space.xl),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.sm),
                  child: Text(_error!,
                      key: const Key('checklists-error'),
                      style: TextStyle(color: scheme.error)),
                ),
              Row(
                children: [
                  FilledButton(
                    key: const Key('checklists-save'),
                    onPressed:
                        _anyChanged && !_anyProblem && !_busy ? _save : null,
                    child: const Text('Save'),
                  ),
                  const SizedBox(width: Space.md),
                  if (_justSaved && !_anyChanged)
                    Text('Saved.',
                        key: const Key('checklists-saved'),
                        style: text.bodyMedium),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(BuildContext context, ChecklistKind k) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final items = _items(k);
    final source = _source(k);
    final fromNotes = source.isNotEmpty;
    final problem = fromNotes ? null : checklistProblem(items);
    final empty = _boxes[k]!.text.trim().isEmpty && !fromNotes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('${k.adjective} checklist', style: text.titleMedium),
            ),
            if (empty)
              TextButton(
                key: Key('checklist-example-${k.name}'),
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _boxes[k]!.text =
                              checklistText(checklistExamples[k]!);
                          _justSaved = false;
                        }),
                child: const Text('Start from an example'),
              ),
          ],
        ),
        const SizedBox(height: Space.xs),
        TextField(
          key: Key('checklist-source-${k.name}'),
          controller: _sources[k],
          enabled: !_busy,
          maxLength: 500,
          buildCounter: (_,
                  {required currentLength,
                  required isFocused,
                  required maxLength}) =>
              null,
          decoration: InputDecoration(
            labelText: 'Path in your notes app (optional)',
            hintText: 'Checklists/${k.adjective}',
            helperText: fromNotes
                ? 'The list is read from this note and cannot be ticked here.'
                : 'Leave empty to write the list below.',
          ),
          onChanged: (_) => setState(() => _justSaved = false),
        ),
        const SizedBox(height: Space.sm),
        TextField(
          key: Key('checklist-box-${k.name}'),
          controller: _boxes[k],
          enabled: !_busy && !fromNotes,
          minLines: 4,
          maxLines: 12,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'One item on each line',
            alignLabelWithHint: true,
            errorText: problem,
            helperText: fromNotes
                ? 'This list is not used while a notes path is set.'
                : null,
          ),
          onChanged: (_) => setState(() => _justSaved = false),
        ),
        const SizedBox(height: Space.xs),
        Text(
          fromNotes
              ? 'Read from $source.'
              : items.isEmpty
                  ? 'No items: there is no ${k.adjective.toLowerCase()} '
                      'checklist.'
                  : '${items.length} ${items.length == 1 ? 'item' : 'items'}'
                      '${_changed(k) ? ', not saved yet' : ''}',
          key: Key('checklist-count-${k.name}'),
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
