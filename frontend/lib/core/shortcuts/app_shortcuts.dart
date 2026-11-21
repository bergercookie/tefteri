/// Keyboard handling for the whole app and the shortcut help overlay.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/planner/new_event_dialog.dart';
import '../../features/planner/new_task_dialog.dart';
import '../../features/settings/sync_controller.dart';
import '../auth_controller.dart';
import '../event_input.dart';
import '../find.dart';
import 'keymap.dart';
import 'page_scroll.dart';

/// True while a text field has the keyboard focus.
bool textFieldHasFocus() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  return context.widget is EditableText ||
      context.findAncestorStateOfType<EditableTextState>() != null;
}

/// True while a text field that has more than one line has the keyboard
/// focus. In such a field Page Up and Page Down move the cursor. A field of one
/// line has no use for them, so they scroll the view even while the user types
/// or while the find bar has the focus.
bool multilineTextFieldHasFocus() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  final editable = context.widget is EditableText
      ? context.widget as EditableText
      : context.findAncestorWidgetOfExactType<EditableText>();
  return editable != null && editable.maxLines != 1;
}

/// An action that is enabled only while [enabled] returns true. A disabled
/// action lets the key event pass on, so a typed character reaches the
/// text field.
class _KeyAction<T extends Intent> extends Action<T> {
  _KeyAction(this._run, this._enabled);

  final void Function(T intent) _run;
  final bool Function(T intent) _enabled;

  @override
  bool isEnabled(T intent) => _enabled(intent);

  @override
  Object? invoke(T intent) {
    _run(intent);
    return null;
  }
}

/// Puts the shortcuts of [appShortcuts] above [child] (the router's
/// navigator) and runs them with [router].
class AppShortcuts extends ConsumerStatefulWidget {
  /// Creates the handler.
  const AppShortcuts({required this.router, required this.child, super.key});

  /// Router used to open views and to find the navigator for the overlay.
  final GoRouter router;

  /// The app below.
  final Widget child;

  @override
  ConsumerState<AppShortcuts> createState() => _AppShortcutsState();
}

class _AppShortcutsState extends ConsumerState<AppShortcuts> {
  NavigatorState? get _navigator =>
      widget.router.routerDelegate.navigatorKey.currentState;

  bool get _signedIn => ref.read(authControllerProvider).signedIn;

  /// No dialog, sheet or menu is open on top of the current view.
  bool get _onView => !(_navigator?.canPop() ?? false);

  bool _plainAllowed() => _onView && !textFieldHasFocus();

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: {
        for (final s in appShortcuts) ...{
          s.activator: s.intent,
          // The same key on a Greek layout, where it makes a Greek letter.
          for (final twin in greekTwins(s.activator)) twin: s.intent,
        },
        // The same key on a Mac.
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
            const FindIntent(),
        for (final twin in greekTwins(
            const SingleActivator(LogicalKeyboardKey.keyF, meta: true)))
          twin: const FindIntent(),
      },
      child: Actions(
        actions: {
          OpenViewIntent: _KeyAction<OpenViewIntent>(
            (i) => widget.router.go(i.path),
            (_) => _signedIn && _plainAllowed(),
          ),
          SyncIntent: _KeyAction<SyncIntent>(
            (_) => ref.read(syncControllerProvider.notifier).syncAll(),
            (i) =>
                _signedIn &&
                !ref.read(syncControllerProvider).busy &&
                (!i.plain || _plainAllowed()),
          ),
          NewTaskIntent: _KeyAction<NewTaskIntent>(
            (_) {
              final context = _navigator?.context;
              if (context != null) showNewTaskDialog(context);
            },
            (_) => _signedIn && _plainAllowed(),
          ),
          NewEventIntent: _KeyAction<NewEventIntent>(
            (_) {
              final context = _navigator?.context;
              if (context != null) {
                showNewEventDialog(context,
                    start: nextFullHour(DateTime.now()));
              }
            },
            (_) => _signedIn && _plainAllowed(),
          ),
          FindIntent: _KeyAction<FindIntent>(
            (_) => ref.read(findProvider.notifier).open(),
            (_) => _signedIn,
          ),
          ShowShortcutsIntent: _KeyAction<ShowShortcutsIntent>(
            (_) {
              final context = _navigator?.context;
              if (context != null) showShortcutHelp(context);
            },
            (_) => _plainAllowed(),
          ),
          // Not while a dialog is open (its own list takes the key) or while the
          // user types in a field of several lines, where the keys move the
          // cursor.
          PageScrollIntent: _KeyAction<PageScrollIntent>(
            (i) {
              final context = _navigator?.context;
              if (context != null) pageScroll(context, forward: i.forward);
            },
            (_) => _signedIn && _onView && !multilineTextFieldHasFocus(),
          ),
          LeaveTextFieldIntent: _KeyAction<LeaveTextFieldIntent>(
            (_) => FocusManager.instance.primaryFocus?.unfocus(),
            (_) => textFieldHasFocus(),
          ),
        },
        // Takes the focus when nothing else has it, so key events always
        // reach the shortcuts above.
        child: Focus(autofocus: true, child: widget.child),
      ),
    );
  }
}

/// Opens the shortcut help overlay.
Future<void> showShortcutHelp(BuildContext context) => showDialog<void>(
      context: context,
      builder: (_) => const ShortcutHelp(),
    );

/// Lists every shortcut of the keymap.
class ShortcutHelp extends StatelessWidget {
  /// Creates the overlay.
  const ShortcutHelp({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      key: const Key('shortcut-help'),
      title: const Text('Keyboard shortcuts'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final s in appShortcuts)
                Padding(
                  key: Key('shortcut-${s.keys}'),
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 72,
                        child: Chip(
                          label: Text(s.keys),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(s.description)),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                'One-key shortcuts do not work while you type in a text '
                'field. Press Esc to leave the field first.',
                style: text.bodySmall,
              ),
              const SizedBox(height: 4),
              Text(
                'On a Greek keyboard, the same keys work: the key for P '
                'makes π, and it opens the Planner.',
                key: const Key('shortcut-help-greek'),
                style: text.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('shortcut-help-close'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
