/// Keyboard handling for the whole app and the shortcut help overlay.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/settings/sync_controller.dart';
import '../auth_controller.dart';
import '../context_filter.dart';
import 'keymap.dart';

/// True while a text field has the keyboard focus.
bool textFieldHasFocus() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  return context.widget is EditableText ||
      context.findAncestorStateOfType<EditableTextState>() != null;
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
      shortcuts: {for (final s in appShortcuts) s.activator: s.intent},
      child: Actions(
        actions: {
          OpenViewIntent: _KeyAction<OpenViewIntent>(
            (i) => widget.router.go(i.path),
            (_) => _signedIn && _plainAllowed(),
          ),
          SetContextIntent: _KeyAction<SetContextIntent>(
            (i) => ref.read(contextFilterProvider.notifier).state = i.filter,
            (_) => _signedIn && _plainAllowed(),
          ),
          SyncIntent: _KeyAction<SyncIntent>(
            (_) => ref.read(syncControllerProvider.notifier).syncAll(),
            (i) =>
                _signedIn &&
                !ref.read(syncControllerProvider).busy &&
                (!i.plain || _plainAllowed()),
          ),
          ShowShortcutsIntent: _KeyAction<ShowShortcutsIntent>(
            (_) {
              final context = _navigator?.context;
              if (context != null) showShortcutHelp(context);
            },
            (_) => _plainAllowed(),
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
