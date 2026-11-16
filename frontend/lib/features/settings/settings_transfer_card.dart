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
                'them into this account. Connections are not included, '
                'because they hold your passwords and tokens.'),
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
    final messenger = ScaffoldMessenger.of(context);
    final String text;
    try {
      final file = await ref.read(planningApiProvider).exportSettings();
      text = const JsonEncoder.withIndent('  ').convert(file);
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      return;
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Export settings'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: SelectableText(text,
                key: const Key('export-settings-text'),
                style: Theme.of(ctx).textTheme.bodySmall),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          FilledButton(
            key: const Key('export-copy-button'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              messenger.showSnackBar(
                  const SnackBar(content: Text('Settings copied.')));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Copy'),
          ),
        ],
      ),
    );
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final imported = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ImportDialog(api: ref.read(planningApiProvider)),
    );
    if (imported == true) {
      ref.invalidate(userSettingsProvider);
      messenger
          .showSnackBar(const SnackBar(content: Text('Settings imported.')));
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
      await widget.api.importSettings(file);
      if (mounted) Navigator.pop(context, true);
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
          onPressed: _busy ? null : () => Navigator.pop(context, false),
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
