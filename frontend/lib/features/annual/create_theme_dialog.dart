/// The dialog that creates a theme project from the planning screen (US4).
/// The server creates the project in the task app first, then labels it.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../theme/theme.dart';
import 'annual_api.dart';
import 'annual_models.dart';

/// Asks for a name and creates the theme. Answers the new theme, the existing
/// theme the user chose to link instead, or null.
Future<ThemeOption?> showCreateThemeDialog(
        BuildContext context, List<TaskConnection> connections) =>
    showDialog<ThemeOption>(
      context: context,
      builder: (_) => CreateThemeDialog(connections: connections),
    );

/// The existing theme of a `theme_exists` answer, or null.
ThemeOption? existingTheme(Object error) {
  if (error is! DioException) return null;
  final data = error.response?.data;
  if (data is! Map) return null;
  final detail = data['detail'];
  final existing =
      data['existing'] ?? (detail is Map ? detail['existing'] : null);
  if (existing is! Map) return null;
  return ThemeOption(
      projectId: '${existing['project_id']}',
      name: '${existing['name'] ?? ''}');
}

/// The create-theme dialog.
class CreateThemeDialog extends ConsumerStatefulWidget {
  /// Creates the dialog for [connections].
  const CreateThemeDialog({required this.connections, super.key});

  /// The task connections a theme can be created in.
  final List<TaskConnection> connections;

  @override
  ConsumerState<CreateThemeDialog> createState() => _CreateThemeDialogState();
}

class _CreateThemeDialogState extends ConsumerState<CreateThemeDialog> {
  final _name = TextEditingController();
  String? _connection;
  String? _error;
  ThemeOption? _existing;
  bool _busy = false;

  List<TaskConnection> get _usable => [
        for (final c in widget.connections)
          if (c.canCreate) c
      ];

  @override
  void initState() {
    super.initState();
    _connection = _usable.isEmpty ? null : _usable.first.id;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Write a name for the theme.');
      return;
    }
    final connection = _connection;
    if (connection == null) {
      setState(() => _error =
          'No task app can create a theme. Connect one in Settings first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _existing = null;
    });
    try {
      final made =
          await ref.read(annualApiProvider).createTheme(connection, name);
      if (mounted) Navigator.of(context).pop(made);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (apiErrorCode(e) == 'theme_exists') {
          _existing =
              existingTheme(e) ?? ThemeOption(projectId: '', name: name);
        } else {
          _error = apiErrorMessage(e);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final existing = _existing;
    return AlertDialog(
      key: const Key('create-theme-dialog'),
      title: const Text('Create a theme'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
                'Tefteri creates a top-level project in your task app and '
                'labels it theme.'),
            const SizedBox(height: Space.sm),
            TextField(
              key: const Key('theme-name'),
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Theme name'),
              onSubmitted: (_) => _create(),
            ),
            if (_usable.length > 1) ...[
              const SizedBox(height: Space.sm),
              DropdownButtonFormField<String>(
                key: const Key('theme-connection'),
                initialValue: _connection,
                decoration: const InputDecoration(labelText: 'Task app'),
                items: [
                  for (final c in _usable)
                    DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) => setState(() => _connection = v),
              ),
            ],
            if (existing != null)
              Container(
                key: const Key('theme-exists-question'),
                margin: const EdgeInsets.only(top: Space.md),
                padding: const EdgeInsets.all(Space.md),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(Corner.md),
                  border: Border.all(color: context.tefteri.rule),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('A theme named "${existing.name}" exists already. '
                        'Link the existing theme instead?'),
                    if (existing.projectId.isNotEmpty)
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.tonal(
                          key: const Key('theme-link-existing'),
                          onPressed: () => Navigator.of(context).pop(existing),
                          child: const Text('Link the existing theme'),
                        ),
                      ),
                  ],
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: Space.sm),
                child: Text(_error!,
                    key: const Key('theme-create-error'),
                    style: TextStyle(color: scheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('theme-create'),
          onPressed: _busy ? null : _create,
          child: Text(_busy ? 'Creating…' : 'Create theme'),
        ),
      ],
    );
  }
}
