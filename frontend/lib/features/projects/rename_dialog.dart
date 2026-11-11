/// Dialogs that write a project name to the task app: rename, and create a
/// theme.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'projects_api.dart';
import 'projects_models.dart';

/// Asks for a new name. [save] writes it and answers an error message, or
/// null when it worked; on an error the dialog stays open and the old name
/// stays everywhere. Pops true after a save.
class RenameDialog extends StatefulWidget {
  /// Creates the dialog for the project called [currentName].
  const RenameDialog(
      {required this.currentName, required this.save, super.key});

  /// The name now.
  final String currentName;

  /// Writes the new name; answers an error message or null.
  final Future<String?> Function(String name) save;

  @override
  State<RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<RenameDialog> {
  late final _name = TextEditingController(text: widget.currentName);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty || name == widget.currentName || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.save(name);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = _name.text.trim();
    return AlertDialog(
      key: const Key('rename-dialog'),
      title: const Text('Rename project'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('rename-field'),
              controller: _name,
              autofocus: true,
              enabled: !_busy,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'New name',
                helperText: 'Tefteri changes the name in your task app first.',
                helperMaxLines: 2,
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline, size: 18, color: scheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_error!,
                          key: const Key('rename-error'),
                          style: TextStyle(color: scheme.error)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('rename-cancel'),
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('rename-save'),
          onPressed: name.isEmpty || name == widget.currentName || _busy
              ? null
              : _submit,
          child: Text(_busy ? 'Saving...' : 'Rename'),
        ),
      ],
    );
  }
}

/// What the user typed in [CreateThemeDialog].
typedef NewTheme = ({String connectionId, String name});

/// Asks for the name of a new theme, and for the task app when there are
/// several. [save] creates it in the task app first, then labels it, and
/// answers an error message or null.
class CreateThemeDialog extends StatefulWidget {
  /// Creates the dialog for the task connections [connections].
  const CreateThemeDialog(
      {required this.connections, required this.save, super.key});

  /// The task connections the theme can go into.
  final List<ConnectionProjects> connections;

  /// Creates the theme; answers an error message or null.
  final Future<String?> Function(NewTheme theme) save;

  @override
  State<CreateThemeDialog> createState() => _CreateThemeDialogState();
}

class _CreateThemeDialogState extends State<CreateThemeDialog> {
  final _name = TextEditingController();
  late String _connection = widget.connections.first.connectionId;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.save((connectionId: _connection, name: name));
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      key: const Key('create-theme-dialog'),
      title: const Text('Create a theme'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('A theme is a long-running home for related work, '
                'such as "Health" or "Open source". Tefteri creates it in '
                'your task app and labels it as a theme.'),
            const SizedBox(height: 12),
            TextField(
              key: const Key('create-theme-name'),
              controller: _name,
              autofocus: true,
              enabled: !_busy,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            if (widget.connections.length > 1) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const Key('create-theme-connection'),
                initialValue: _connection,
                decoration: const InputDecoration(labelText: 'Task app'),
                items: [
                  for (final c in widget.connections)
                    DropdownMenuItem(
                        value: c.connectionId, child: Text(c.name)),
                ],
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _connection = v ?? _connection),
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!,
                    key: const Key('create-theme-error'),
                    style: TextStyle(color: scheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('create-theme-save'),
          onPressed: _name.text.trim().isEmpty || _busy ? null : _submit,
          child: Text(_busy ? 'Creating...' : 'Create theme'),
        ),
      ],
    );
  }
}

/// The "Create a theme" action, for every place that offers it. It reads the
/// task connections, asks for a name and creates the theme in the task app
/// and then here. Answers true when a theme was created.
Future<bool> createTheme(BuildContext context, WidgetRef ref) async {
  final api = ref.read(projectsApiProvider);
  final messenger = ScaffoldMessenger.of(context);
  final List<ConnectionProjects> connections;
  try {
    connections = (await api.classification()).connections;
  } on DioException catch (e) {
    messenger.showSnackBar(SnackBar(
        content:
            Text(projectsError(e, 'read your task apps to create a theme'))));
    return false;
  }
  if (connections.isEmpty) {
    messenger.showSnackBar(const SnackBar(
        content: Text('Connect a task app in Settings first. Tefteri creates '
            'the theme there.')));
    return false;
  }
  if (!context.mounted) return false;
  final done = await showDialog<bool>(
    context: context,
    builder: (_) => CreateThemeDialog(
      connections: connections,
      save: (t) async {
        try {
          await api.create(
              connectionId: t.connectionId,
              name: t.name,
              label: ProjectLabel.theme);
          return null;
        } on DioException catch (e) {
          return projectsError(e, 'create the theme');
        }
      },
    ),
  );
  if (done == true) {
    ref.invalidate(unsortedCountProvider);
    messenger.showSnackBar(const SnackBar(content: Text('Theme created.')));
  }
  return done == true;
}
