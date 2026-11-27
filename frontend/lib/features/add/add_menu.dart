/// The round "+" button on every screen, and the menu that it opens: a daily note, a task or a
/// calendar event.
library;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../../core/event_input.dart';
import '../../theme/theme.dart';
import '../daily/daily_note_button.dart';
import '../planner/new_event_dialog.dart';
import '../planner/new_task_dialog.dart';

/// The height below a page that the button keeps free: its height and the gap around it.
const double addButtonClearance = 72;

/// Below this width the button is a plain circle, to leave room on a phone.
const double addButtonWideWidth = 600;

/// A button at the bottom right of every screen. A tap opens the menu of [showAddMenu]. The key
/// A does the same, and each choice has a key of its own (D, N and Shift+N).
///
/// On a phone it is a round "+". On a wider screen it also says "Add", because a "+" alone does
/// not tell what it adds.
class AddButton extends StatelessWidget {
  /// Creates the button.
  const AddButton({super.key});

  @override
  Widget build(BuildContext context) {
    void open() => showAddMenu(context);
    if (MediaQuery.sizeOf(context).width >= addButtonWideWidth) {
      return FloatingActionButton.extended(
        key: const Key('add-button'),
        tooltip: 'Add a note, a task or an event (A)',
        onPressed: open,
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      );
    }
    return FloatingActionButton(
      key: const Key('add-button'),
      tooltip: 'Add a note, a task or an event',
      onPressed: open,
      child: const Icon(Icons.add),
    );
  }
}

/// Starts a new calendar event, at the next full hour.
Future<void> startNewEvent(BuildContext context) =>
    showNewEventDialog(context, start: nextFullHour(DateTime.now()));

/// Opens the menu with the three things to add. A choice closes the menu and opens its own
/// sheet or pop-up.
Future<void> showAddMenu(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheet) => _AddMenu(
        onChoose: (open) {
          Navigator.of(sheet).pop();
          open(context);
        },
      ),
    );

bool get _hasKeyboard =>
    defaultTargetPlatform != TargetPlatform.android &&
    defaultTargetPlatform != TargetPlatform.iOS;

class _AddMenu extends StatelessWidget {
  const _AddMenu({required this.onChoose});

  final void Function(Future<void> Function(BuildContext context) open)
      onChoose;

  @override
  Widget build(BuildContext context) {
    void note() => onChoose(showDailyNoteSheet);
    void task() => onChoose(showNewTaskDialog);
    void event() => onChoose(startNewEvent);
    return CallbackShortcuts(
      // The same keys as everywhere in the app, so that a key works also with the menu open.
      bindings: {
        const CharacterActivator('d'): note,
        const CharacterActivator('n'): task,
        const CharacterActivator('N'): event,
      },
      // Scrolls on a short screen (a phone held sideways), so that nothing is cut off.
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.sm, 0, Space.sm, Space.lg),
        child: Column(
          key: const Key('add-menu'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.sm),
              child:
                  Text('Add', style: Theme.of(context).textTheme.titleMedium),
            ),
            _Option(
              key: const Key('add-note'),
              icon: Icons.edit_note_outlined,
              title: 'Daily note',
              subtitle: 'Write a line for the note of a day',
              keys: 'D',
              autofocus: true,
              onTap: note,
            ),
            _Option(
              key: const Key('add-task'),
              icon: Icons.radio_button_unchecked,
              title: 'Task',
              subtitle: 'Create a task in your task app',
              keys: 'N',
              onTap: task,
            ),
            _Option(
              key: const Key('add-event'),
              icon: Icons.event_available_outlined,
              title: 'Calendar event',
              subtitle: 'Schedule an event in a calendar',
              keys: 'Shift+N',
              onTap: event,
            ),
          ],
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.keys,
    required this.onTap,
    this.autofocus = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String keys;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return ListTile(
      autofocus: autofocus,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Corner.md)),
      leading: Icon(icon, color: scheme.primary),
      title: Text(title),
      subtitle: Text(subtitle),
      // The key of the choice, on a device that has a keyboard.
      trailing: _hasKeyboard
          ? DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: scheme.outlineVariant),
                borderRadius: BorderRadius.circular(Corner.sm),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: Space.sm, vertical: Space.xs),
                child: Text(keys,
                    style: text.labelMedium
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ),
            )
          : null,
      onTap: onTap,
    );
  }
}
