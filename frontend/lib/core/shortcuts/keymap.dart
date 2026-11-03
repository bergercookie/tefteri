/// The central keymap: every view and keyboard shortcut of the app.
///
/// The navigation drawer, the shortcut handler and the help overlay are all
/// built from these lists, so they cannot drift apart.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../context_filter.dart';

/// A screen that the drawer and the keyboard can open.
@immutable
class AppView {
  /// Creates a view at [path]; [key] is its plain-key shortcut, if any.
  const AppView(this.label, this.path, [this.key]);

  /// Name shown to the user.
  final String label;

  /// Router location.
  final String path;

  /// Lower-case character that opens the view, or null.
  final String? key;
}

/// All views in drawer order. Change password and Users have no shortcut.
const appViews = [
  AppView('Planner', '/', 'p'),
  AppView('Today', '/daily', 't'),
  AppView('Week', '/week', 'w'),
  AppView('Month', '/month', 'm'),
  AppView('Year', '/year', 'y'),
  AppView('Goals', '/goals', 'g'),
  AppView('Reviews', '/review', 'r'),
  AppView('Notes', '/notes', 'n'),
  AppView('Conflicts', '/conflicts', 'x'),
  AppView('Connections', '/settings', 's'),
  AppView('Change password', '/password'),
];

/// Opens the view at [path].
class OpenViewIntent extends Intent {
  /// Creates the intent.
  const OpenViewIntent(this.path);

  /// Router location.
  final String path;
}

/// Syncs all connections.
class SyncIntent extends Intent {
  /// Creates the intent.
  const SyncIntent();
}

/// Sets the global all/life/work filter.
class SetContextIntent extends Intent {
  /// Creates the intent.
  const SetContextIntent(this.filter);

  /// New filter value.
  final ContextFilter filter;
}

/// Opens the shortcut help overlay.
class ShowShortcutsIntent extends Intent {
  /// Creates the intent.
  const ShowShortcutsIntent();
}

/// Moves the focus out of a text field so plain-key shortcuts work again.
class LeaveTextFieldIntent extends Intent {
  /// Creates the intent.
  const LeaveTextFieldIntent();
}

/// One keyboard shortcut.
@immutable
class AppShortcut {
  /// Creates a shortcut.
  const AppShortcut({
    required this.keys,
    required this.description,
    required this.activator,
    required this.intent,
  });

  /// Key name for the user, such as `W`, `F5` or `?`.
  final String keys;

  /// What the shortcut does.
  final String description;

  /// The key that triggers it.
  final ShortcutActivator activator;

  /// What happens.
  final Intent intent;

  /// True for a single character key. Such keys are ignored while the user
  /// types in a text field, so the character goes into the field.
  bool get plain => activator is CharacterActivator;
}

/// Every shortcut, in the order of the help overlay.
final List<AppShortcut> appShortcuts = [
  for (final v in appViews)
    if (v.key != null)
      AppShortcut(
        keys: v.key!.toUpperCase(),
        description: 'Open ${v.label}',
        activator: CharacterActivator(v.key!),
        intent: OpenViewIntent(v.path),
      ),
  const AppShortcut(
    keys: 'F5',
    description: 'Sync all connections',
    activator: SingleActivator(LogicalKeyboardKey.f5),
    intent: SyncIntent(),
  ),
  for (final (i, f) in ContextFilter.values.indexed)
    AppShortcut(
      keys: '${i + 1}',
      description: 'Show ${switch (f) {
        ContextFilter.all => 'all items',
        ContextFilter.life => 'life items only',
        ContextFilter.work => 'work items only',
      }}',
      activator: CharacterActivator('${i + 1}'),
      intent: SetContextIntent(f),
    ),
  const AppShortcut(
    keys: '?',
    description: 'Show this list of shortcuts',
    activator: CharacterActivator('?'),
    intent: ShowShortcutsIntent(),
  ),
  const AppShortcut(
    keys: 'Esc',
    description: 'Leave the text field (then the one-key shortcuts work)',
    activator: SingleActivator(LogicalKeyboardKey.escape),
    intent: LeaveTextFieldIntent(),
  ),
];
