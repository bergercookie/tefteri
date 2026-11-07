/// Shared look of the Settings and Admin settings pages: a short list of
/// pages, each with an icon, a title and one line of help.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Widest the list gets, so that it stays readable on a large window.
const double settingsListWidth = 560;

/// One page in a settings list.
class SettingsEntry {
  /// Creates an entry that opens [path].
  const SettingsEntry({
    required this.keyName,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.path,
  });

  /// Part of the widget key (`settings-<keyName>`).
  final String keyName;

  /// Icon at the left.
  final IconData icon;

  /// Name of the page.
  final String title;

  /// One line that tells what the page is for.
  final String subtitle;

  /// Router location of the page.
  final String path;
}

/// A list of [entries] at the left edge, no wider than [settingsListWidth].
class SettingsList extends StatelessWidget {
  /// Creates the list.
  const SettingsList({required this.entries, this.footer, super.key});

  /// Shown below the pages, for example a card of settings.
  final Widget? footer;

  /// The pages to show.
  final List<SettingsEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: settingsListWidth),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final e in entries)
              Card(
                child: ListTile(
                  key: Key('settings-${e.keyName}'),
                  leading: Icon(e.icon),
                  title: Text(e.title),
                  subtitle: Text(e.subtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go(e.path),
                ),
              ),
            if (footer != null) footer!,
          ],
        ),
      ),
    );
  }
}
