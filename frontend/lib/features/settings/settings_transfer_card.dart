/// Export and import of the user's settings: a JSON file body that can be
/// copied out and pasted into another account or installation.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/planning_api.dart';
import '../../theme/theme.dart';
import 'planner_settings_card.dart';

/// Turns pasted text into the object to import, or throws a [FormatException]
/// whose message is meant for the user.
Map<String, dynamic> parseSettingsExport(String text) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    throw const FormatException('This is not valid JSON.');
  }
  if (decoded is! Map || decoded['format'] != 'tefteri-settings') {
    throw const FormatException('This is not a Tefteri settings export.');
  }
  return Map<String, dynamic>.from(decoded);
}

/// A card with an Export and an Import button.
class SettingsTransferCard extends ConsumerWidget {
  /// Creates the card.
  const SettingsTransferCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      key: const Key('settings-transfer-card'),
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Export and import',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: Space.xs),
            const Text('Copy your planner settings and checklists, or paste '
                'them into this account. You can include your connections '
                'and the calendar for new events when you export.'),
            const SizedBox(height: Space.sm),
            Wrap(spacing: Space.sm, children: [
              OutlinedButton.icon(
                key: const Key('export-settings-button'),
                icon: const Icon(Icons.upload),
                label: const Text('Export'),
                onPressed: () => _export(context, ref),
              ),
              OutlinedButton.icon(
                key: const Key('import-settings-button'),
                icon: const Icon(Icons.download),
                label: const Text('Import'),
                onPressed: () => _import(context, ref),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _ExportDialog(api: ref.read(planningApiProvider)),
    );
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final message = await showDialog<String>(
      context: context,
      builder: (ctx) => _ImportDialog(api: ref.read(planningApiProvider)),
    );
    if (message != null) {
      ref.invalidate(userSettingsProvider);
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

class _ImportDialog extends StatefulWidget {
  const _ImportDialog({required this.api});

  final PlanningApi api;

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final _controller = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final Map<String, dynamic> file;
    try {
      file = parseSettingsExport(_controller.text);
    } on FormatException catch (e) {
      setState(() => _error = e.message);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.api.importSettings(file);
      if (mounted) Navigator.pop(context, result.message);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = apiErrorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import settings'),
      content: SizedBox(
        width: 480,
        child: TextField(
          key: const Key('import-settings-field'),
          controller: _controller,
          minLines: 8,
          maxLines: 12,
          decoration: InputDecoration(
            hintText: 'Paste the exported settings here',
            errorText: _error,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('import-submit-button'),
          onPressed: _busy ? null : _submit,
          child: const Text('Import'),
        ),
      ],
    );
  }
}

class _ExportDialog extends StatefulWidget {
  const _ExportDialog({required this.api});

  final PlanningApi api;

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  bool _includeConnections = false;
  bool _busy = false;
  String? _error;
  String? _text;

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = await widget.api
          .exportSettings(includeConnections: _includeConnections);
      if (mounted) {
        setState(
            () => _text = const JsonEncoder.withIndent('  ').convert(file));
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = _text;
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Export settings'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: text != null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_includeConnections)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Space.sm),
                        child: Text(
                          'This text holds your passwords and tokens. Keep it '
                          'private.',
                          key: const Key('export-secret-warning'),
                          style: TextStyle(color: scheme.error),
                        ),
                      ),
                    SelectableText(text,
                        key: const Key('export-settings-text'),
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CheckboxListTile(
                      key: const Key('export-include-connections'),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('Include connections'),
                      subtitle: const Text(
                          'Adds your connections with their passwords and '
                          'tokens, and the calendar for new events. Anyone '
                          'who has the text can use them.'),
                      value: _includeConnections,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _includeConnections = v!),
                    ),
                    if (_error != null)
                      Text(_error!, style: TextStyle(color: scheme.error)),
                  ],
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        if (text == null)
          FilledButton(
            key: const Key('export-run-button'),
            onPressed: _busy ? null : _run,
            child: const Text('Export'),
          )
        else
          FilledButton(
            key: const Key('export-copy-button'),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);
              await Clipboard.setData(ClipboardData(text: text));
              messenger.showSnackBar(
                  const SnackBar(content: Text('Settings copied.')));
              navigator.pop();
            },
            child: const Text('Copy'),
          ),
      ],
    );
  }
}
