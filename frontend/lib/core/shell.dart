/// Common scaffold: navigation, header with the context switch and the sync
/// button.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/settings/sync_controller.dart';
import '../theme/theme.dart';
import 'auth_controller.dart';
import 'pane_widths.dart';
import 'shortcuts/app_shortcuts.dart';
import 'shortcuts/keymap.dart';
import 'versions.dart';

/// Window width from which the navigation is a permanent rail on the left
/// instead of a drawer behind a menu button.
const double railMinWidth = 960;

/// Window width from which the rail shows labels and shortcut keys beside the
/// icons instead of below them.
const double railExtendedMinWidth = 1180;

const double _railCompactWidth = 76;
const double _sidebarMinWidth = 200;

/// Distance from the rail's left edge to the icons (and the mark) when the
/// rail shows labels: the list's side padding plus the item's own.
const double _railIndent = Space.md + Space.lg;

/// The icon of each view, all in the same outlined style.
const _viewIcons = <String, IconData>{
  '/': Icons.view_column_outlined,
  '/daily': Icons.today_outlined,
  '/week': Icons.view_week_outlined,
  '/month': Icons.calendar_view_month_outlined,
  '/year': Icons.calendar_month_outlined,
  '/goals': Icons.flag_outlined,
  '/projects': Icons.account_tree_outlined,
  '/review': Icons.auto_stories_outlined,
  '/conflicts': Icons.call_split_outlined,
  '/settings': Icons.tune_outlined,
};

/// Router location of the current page, or '' without a router (tests).
String _currentPath(BuildContext context) {
  final router = GoRouter.maybeOf(context);
  return router?.routeInformationProvider.value.uri.path ?? '';
}

bool _isCurrent(String current, String path) => path == '/'
    ? current == '/'
    : current == path || current.startsWith('$path/');

/// App scaffold shared by all views: a navigation rail (or a drawer on narrow
/// windows), a header with the title and the context switch, and the page.
class AppShell extends ConsumerWidget {
  /// Creates a shell showing [body] under [title].
  const AppShell({
    required this.title,
    required this.body,
    this.backTo,
    super.key,
  });

  /// Title shown in the header.
  final String title;

  /// Router location of the parent page. When set, the header shows a back
  /// button (used by the pages under Settings and Admin settings).
  final String? backTo;

  /// View content.
  final Widget body;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<SyncState>(syncControllerProvider, (prev, next) {
      if (prev == null || !prev.busy || next.busy || !next.announce) return;
      final text = next.error ??
          (next.failures.isEmpty
              ? 'Sync finished.'
              : '${next.failures.length} connection(s) need attention. '
                  'Open Connections for details.');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    });
    return LayoutBuilder(builder: (context, c) {
      final rail = c.maxWidth >= railMinWidth;
      final extended = c.maxWidth >= railExtendedMinWidth;
      // The labelled sidebar is as wide as the user dragged it, but never more
      // than two fifths of the window.
      final sidebar = ref.watch(sidebarWidthProvider);
      final railWidth = extended
          ? sidebar.clamp(_sidebarMinWidth, c.maxWidth * 0.4).toDouble()
          : _railCompactWidth;
      return Scaffold(
        drawer: rail
            ? null
            : const Drawer(child: SafeArea(child: _NavPanel(extended: true))),
        body: SafeArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (rail) ...[
                SizedBox(
                  width: railWidth,
                  child: ColoredBox(
                    color: Theme.of(context).colorScheme.surface,
                    child: _NavPanel(extended: extended, onRail: true),
                  ),
                ),
                if (extended)
                  ResizeHandle(
                    key: const Key('sidebar-resize'),
                    label: 'Resize the sidebar',
                    onDrag: (dx) => ref
                        .read(sidebarWidthProvider.notifier)
                        .by(dx, cap: c.maxWidth * 0.4),
                    onEnd: () => ref.read(sidebarWidthProvider.notifier).save(),
                    onReset: () =>
                        ref.read(sidebarWidthProvider.notifier).reset(),
                  )
                else
                  const VerticalDivider(width: 1),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(
                      title: title,
                      backTo: backTo,
                      showMenu: !rail,
                    ),
                    const Divider(height: 1),
                    Expanded(child: body),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

/// Title and the header buttons.
class _Header extends ConsumerWidget {
  const _Header({
    required this.title,
    required this.backTo,
    required this.showMenu,
  });

  final String title;
  final String? backTo;
  final bool showMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncControllerProvider);
    return Padding(
      padding: const EdgeInsets.all(Space.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (showMenu)
                Builder(
                  builder: (context) => IconButton(
                    tooltip:
                        MaterialLocalizations.of(context).openAppDrawerTooltip,
                    icon: const Icon(Icons.menu),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  ),
                ),
              if (backTo != null)
                IconButton(
                  key: const Key('back-button'),
                  tooltip: 'Back',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => context.go(backTo!),
                ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                      left: showMenu || backTo != null ? Space.xs : Space.md),
                  child: Text(title,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineSmall),
                ),
              ),
              IconButton(
                key: const Key('shortcuts-button'),
                tooltip: 'Keyboard shortcuts (?)',
                icon: const Icon(Icons.keyboard_outlined),
                onPressed: () => showShortcutHelp(context),
              ),
              IconButton(
                key: const Key('sync-button'),
                tooltip: 'Sync (F5)',
                icon: const Icon(Icons.sync),
                onPressed: sync.busy
                    ? null
                    : () => ref.read(syncControllerProvider.notifier).syncAll(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The list of views, Admin settings and Sign out. Used by the rail (compact
/// or [extended]) and, always extended, by the drawer.
class _NavPanel extends ConsumerWidget {
  const _NavPanel({required this.extended, this.onRail = false});

  final bool extended;

  /// True in the permanent rail; false in the drawer, which closes itself
  /// before it navigates.
  final bool onRail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(authControllerProvider).isAdmin;
    final current = _currentPath(context);

    Widget item(String key, String label, IconData icon, String path,
            {String? shortcut}) =>
        _NavItem(
          key: Key(key),
          label: label,
          icon: icon,
          shortcut: shortcut,
          selected: _isCurrent(current, path),
          extended: extended,
          onTap: () {
            if (!onRail) Navigator.of(context).pop();
            context.go(path);
          },
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          // The mark lines up with the icons below it.
          padding: EdgeInsets.fromLTRB(
              extended ? _railIndent : 0, Space.lg, Space.lg, Space.lg),
          child: Align(
            alignment: extended ? Alignment.centerLeft : Alignment.center,
            child: TefteriWordmark(size: 26, showName: extended),
          ),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.symmetric(
                horizontal: extended ? Space.md : Space.sm),
            children: [
              for (final v in appViews)
                item('nav-${v.path}', v.label,
                    _viewIcons[v.path] ?? Icons.circle_outlined, v.path,
                    shortcut: v.key?.toUpperCase()),
              if (isAdmin)
                item('nav-/admin', 'Admin settings',
                    Icons.admin_panel_settings_outlined, '/admin'),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: EdgeInsets.all(extended ? Space.md : Space.sm),
          child: _NavItem(
            key: const Key('sign-out'),
            label: 'Sign out',
            icon: Icons.logout,
            selected: false,
            extended: extended,
            onTap: () {
              if (!onRail) Navigator.of(context).pop();
              ref.read(authControllerProvider.notifier).logout();
            },
          ),
        ),
        if (extended) const _AppVersionLabel(),
      ],
    );
  }
}

/// The version of the client app, under the Sign out button. It shows
/// nothing while the version is unknown.
class _AppVersionLabel extends ConsumerWidget {
  const _AppVersionLabel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(appVersionProvider).valueOrNull;
    if (version == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(_railIndent, 0, Space.md, Space.md),
      child: Text(
        'Version $version',
        key: const Key('nav-app-version'),
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}

/// One entry of the navigation. The current view has a filled background and
/// a bar on its left edge, like a tab in a notebook.
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.extended,
    required this.onTap,
    this.shortcut,
    super.key,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool extended;
  final VoidCallback onTap;
  final String? shortcut;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final fg = selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    final style = (extended ? text.bodyMedium : text.labelSmall)?.copyWith(
      color: fg,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
    );
    final content = extended
        ? Row(
            children: [
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: Space.md),
              Expanded(child: Text(label, style: style)),
              if (shortcut != null)
                Text(shortcut!,
                    style: text.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.7))),
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: fg),
              const SizedBox(height: 2),
              Text(label,
                  style: style,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center),
            ],
          );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: selected ? scheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(Corner.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: scheme.primaryContainer.withValues(alpha: 0.45),
          child: Stack(
            children: [
              if (selected)
                Positioned(
                  left: 0,
                  top: 6,
                  bottom: 6,
                  child: Container(width: 3, color: scheme.primary),
                ),
              Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: extended ? Space.lg : Space.xs,
                    vertical: extended ? Space.sm + 2 : Space.sm),
                child: content,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
