/// The round "+" button on every screen that adds a line to the daily note.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/planning_models.dart';
import '../../core/planning_api.dart';
import '../../theme/theme.dart';
import 'daily_providers.dart';

/// The day that the "+" button writes to. The daily view sets it to the day that it shows, so
/// that a note added while looking at another day goes to that day. Null means today.
final dailyNoteDayProvider = StateProvider<DateTime?>((ref) => null);

/// The text that the user has typed and not added yet. A pop-up that closes by accident (a tap
/// beside it, the back button) does not lose it: it is there when the pop-up opens again.
final dailyNoteDraftProvider = StateProvider<String>((ref) => '');

/// Below this width the button is a plain circle, to leave room on a phone.
const double dailyNoteButtonWideWidth = 600;

/// The height below a page that the button keeps free: its height and the gap around it.
const double dailyNoteButtonClearance = 72;

/// A button at the bottom right: it opens a small sheet to write a line for the daily note.
///
/// On a phone it is a round "+". On a wider screen it also says "Note", because a "+" alone does
/// not tell what it adds (the Today view has a "+" to add a task as well).
class DailyNoteButton extends StatelessWidget {
  /// Creates the button.
  const DailyNoteButton({super.key});

  @override
  Widget build(BuildContext context) {
    void open() => showDailyNoteSheet(context);
    if (MediaQuery.sizeOf(context).width >= dailyNoteButtonWideWidth) {
      return FloatingActionButton.extended(
        key: const Key('daily-note-fab'),
        tooltip: 'Add to the daily note',
        onPressed: open,
        icon: const Icon(Icons.add),
        label: const Text('Note'),
      );
    }
    return FloatingActionButton(
      key: const Key('daily-note-fab'),
      tooltip: 'Add to the daily note',
      onPressed: open,
      child: const Icon(Icons.add),
    );
  }
}

/// Opens the sheet that adds a line to the daily note.
Future<void> showDailyNoteSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => const DailyNoteSheet(),
    );

/// The sheet: the day, a text field and a button. The text goes to the end of the note.
class DailyNoteSheet extends ConsumerStatefulWidget {
  /// Creates the sheet.
  const DailyNoteSheet({super.key});

  @override
  ConsumerState<DailyNoteSheet> createState() => _DailyNoteSheetState();
}

class _DailyNoteSheetState extends ConsumerState<DailyNoteSheet> {
  late final TextEditingController _text;
  late DateTime _day;
  bool _busy = false;
  String? _error;

  DateTime get _today {
    final now = ref.read(dailyClockProvider)();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: ref.read(dailyNoteDraftProvider));
    final chosen = ref.read(dailyNoteDayProvider);
    _day = chosen == null
        ? _today
        : DateTime(chosen.year, chosen.month, chosen.day);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _isToday => dateKey(_day) == dateKey(_today);

  String get _dayLabel => _isToday ? 'Today, ${dateKey(_day)}' : dateKey(_day);

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) setState(() => _day = picked);
  }

  Future<void> _add() async {
    final text = _text.text.trim();
    if (text.isEmpty || _busy) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final key = dateKey(_day);
    final label = _isToday ? 'today’s note' : 'the note of $key';
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(planningApiProvider).appendToDailyNote(key, text);
    } on Object catch (e) {
      // The text stays in the field, so that nothing is lost.
      if (mounted) {
        setState(() {
          _busy = false;
          _error = apiErrorMessage(e);
        });
      }
      return;
    }
    ref.read(dailyNoteDraftProvider.notifier).state = '';
    ref.invalidate(dayViewProvider(key));
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text('Added to $label.')));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return CallbackShortcuts(
      // Ctrl+Enter (Cmd+Enter on a Mac) adds the line, like the button.
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _add,
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): _add,
      },
      child: Padding(
        // The sheet rises above the keyboard.
        padding: EdgeInsets.fromLTRB(Space.lg, 0, Space.lg,
            MediaQuery.viewInsetsOf(context).bottom + Space.lg),
        child: Column(
          key: const Key('daily-note-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                    child:
                        Text('Add to the daily note', style: text.titleMedium)),
                TextButton.icon(
                  key: const Key('daily-note-day'),
                  onPressed: _busy ? null : _pickDay,
                  icon: const Icon(Icons.calendar_today_outlined, size: 18),
                  label: Text(_dayLabel),
                ),
              ],
            ),
            const SizedBox(height: Space.sm),
            TextField(
              key: const Key('daily-note-field'),
              controller: _text,
              autofocus: true,
              minLines: 3,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              keyboardType: TextInputType.multiline,
              onChanged: (v) {
                ref.read(dailyNoteDraftProvider.notifier).state = v;
                setState(() {});
              },
              decoration: const InputDecoration(
                hintText: 'What do you want to remember about this day?',
              ),
            ),
            const SizedBox(height: Space.sm),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: Text(_error!,
                    key: const Key('daily-note-error'),
                    style: text.bodyMedium?.copyWith(color: scheme.error)),
              ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Added at the end. The text that is there stays.',
                    style: text.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(width: Space.sm),
                FilledButton(
                  key: const Key('daily-note-save'),
                  onPressed: _busy || _text.text.trim().isEmpty ? null : _add,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Add to note'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
