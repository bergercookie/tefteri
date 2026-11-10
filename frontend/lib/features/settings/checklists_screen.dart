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
    'Review the goals of the month',
    'Check the budget',
    'Set the goals for next month',
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

  /// The lists as the server has them; the boxes are measured against these.
  Map<ChecklistKind, List<String>>? _saved;
  bool _busy = false;
  bool _justSaved = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _boxes.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> _items(ChecklistKind k) => parseChecklistText(_boxes[k]!.text);

  bool _changed(ChecklistKind k) =>
      _saved != null && !_same(_items(k), _saved![k] ?? const []);

  static bool _same(List<String> a, List<String> b) =>
      a.length == b.length &&
      [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((x) => x);

  bool get _anyChanged => ChecklistKind.values.any(_changed);

  bool get _anyProblem =>
      ChecklistKind.values.any((k) => checklistProblem(_items(k)) != null);

  /// Fills the boxes from the server the first time, and after a save.
  void _load(UserSettings s) {
    _saved = {for (final k in ChecklistKind.values) k: s.itemsOf(k)};
    for (final k in ChecklistKind.values) {
      _boxes[k]!.text = checklistText(_saved![k]!);
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
      _justSaved = false;
    });
    try {
      // Only the lists that changed are sent: a list that someone else changed
      // on another device is not overwritten by an old copy.
      final saved = await ref.read(planningApiProvider).updateSettings(
        checklists: {
          for (final k in ChecklistKind.values)
            if (_changed(k)) k: _items(k),
        },
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
                'list starts clean each week, month or year.',
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
    final problem = checklistProblem(items);
    final empty = _boxes[k]!.text.trim().isEmpty;
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
          key: Key('checklist-box-${k.name}'),
          controller: _boxes[k],
          enabled: !_busy,
          minLines: 4,
          maxLines: 12,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'One item on each line',
            alignLabelWithHint: true,
            errorText: problem,
          ),
          onChanged: (_) => setState(() => _justSaved = false),
        ),
        const SizedBox(height: Space.xs),
        Text(
          items.isEmpty
              ? 'No items: there is no ${k.adjective.toLowerCase()} checklist.'
              : '${items.length} ${items.length == 1 ? 'item' : 'items'}'
                  '${_changed(k) ? ', not saved yet' : ''}',
          key: Key('checklist-count-${k.name}'),
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
