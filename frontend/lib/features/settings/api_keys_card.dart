/// Settings card: API keys, to connect an AI assistant (MCP) to tefteri.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/planning_models.dart';
import '../../theme/theme.dart';
import 'api_keys.dart';

/// Lists the API keys of the user, makes new ones and revokes old ones. A key
/// lets an AI assistant that speaks MCP read and change the plan of the user.
class ApiKeysCard extends ConsumerWidget {
  /// Creates the card.
  const ApiKeysCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final keys = ref.watch(apiKeysProvider);
    final url = ref.watch(mcpUrlProvider);
    return Card(
      key: const Key('api-keys-card'),
      margin: const EdgeInsets.only(top: Space.lg),
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('API keys and MCP', style: text.titleMedium),
            const SizedBox(height: Space.xs),
            Text(
              'An API key lets an AI assistant that speaks MCP, such as '
              'Claude, read and change your plan: your tasks, your calendar '
              'and your reviews. Make a key for each tool, so that you can '
              'revoke one without the others.',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: Space.md),
            Row(
              children: [
                Expanded(
                  child: SelectableText(url,
                      key: const Key('mcp-url'), style: text.bodyMedium),
                ),
                IconButton(
                  key: const Key('copy-mcp-url'),
                  tooltip: 'Copy the address of the MCP server',
                  icon: const Icon(Icons.copy),
                  onPressed: () => _copy(context, url, 'The address'),
                ),
              ],
            ),
            const SizedBox(height: Space.sm),
            keys.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(Space.md),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text(apiErrorMessage(e),
                  key: const Key('api-keys-error'),
                  style: TextStyle(color: scheme.error)),
              data: (list) => list.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: Space.sm),
                      child: Text('You have no API keys yet.',
                          key: const Key('api-keys-empty'),
                          style: text.bodyMedium),
                    )
                  : Column(children: [
                      for (final k in list) _KeyRow(info: k),
                    ]),
            ),
            const SizedBox(height: Space.sm),
            FilledButton.icon(
              key: const Key('create-api-key'),
              icon: const Icon(Icons.vpn_key_outlined),
              label: const Text('Create an API key'),
              onPressed: () => _create(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _NameDialog(),
    );
    if (name == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final made = await ref.read(apiKeysApiProvider).create(name);
      ref.invalidate(apiKeysProvider);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _NewKeyDialog(made: made),
      );
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }
}

Future<void> _copy(BuildContext context, String value, String what) async {
  final messenger = ScaffoldMessenger.of(context);
  await Clipboard.setData(ClipboardData(text: value));
  messenger.showSnackBar(SnackBar(content: Text('$what is copied.')));
}

class _KeyRow extends ConsumerWidget {
  const _KeyRow({required this.info});

  final ApiKeyInfo info;

  String _when(DateTime d) => '${dateKey(d)} ${hhmm(d)}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final colors = context.tefteri;
    final used = info.lastUsedAt;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.rule)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.sm),
        child: Row(
          children: [
            const Icon(Icons.vpn_key_outlined),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(info.name,
                      key: Key('api-key-name-${info.id}'),
                      style: text.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w500)),
                  Text(
                    '${info.prefix}... Made ${_when(info.createdAt)}. '
                    '${used == null ? 'Never used.' : 'Used ${_when(used)}.'}',
                    key: Key('api-key-detail-${info.id}'),
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
            TextButton(
              key: Key('revoke-${info.id}'),
              onPressed: () => _revoke(context, ref),
              child: const Text('Revoke'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _revoke(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('revoke-confirm'),
        title: Text('Revoke "${info.name}"?'),
        content: const Text(
            'The tool that uses this key is signed out at once. You cannot '
            'undo this. You can make a new key.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              key: const Key('revoke-confirm-yes'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Revoke')),
        ],
      ),
    );
    if (sure != true) return;
    try {
      await ref.read(apiKeysApiProvider).revoke(info.id);
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
    ref.invalidate(apiKeysProvider);
  }
}

/// Asks for the name of a new key.
class _NameDialog extends StatefulWidget {
  const _NameDialog();

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _name = TextEditingController(text: 'Claude');

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isNotEmpty) Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        key: const Key('api-key-name-dialog'),
        title: const Text('Create an API key'),
        content: TextField(
          key: const Key('api-key-name-field'),
          controller: _name,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(
            labelText: 'Name',
            helperText: 'The tool that will use the key, for example Claude.',
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _submit(),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          FilledButton(
              key: const Key('api-key-name-create'),
              onPressed: _name.text.trim().isEmpty ? null : _submit,
              child: const Text('Create')),
        ],
      );
}

/// Shows the new key once, with the lines that connect a tool to tefteri.
class _NewKeyDialog extends ConsumerWidget {
  const _NewKeyDialog({required this.made});

  final NewApiKey made;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final url = ref.watch(mcpUrlProvider);
    final command = claudeCodeCommand(url, made.key);
    final config = mcpClientConfig(url, made.key);
    Widget block(Key key, String title, String value, Key copyKey) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: text.titleSmall)),
                TextButton.icon(
                  key: copyKey,
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy'),
                  onPressed: () => _copy(context, value, title),
                ),
              ],
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Space.sm),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(Corner.sm),
              ),
              child: SelectableText(value, key: key, style: text.bodySmall),
            ),
          ],
        );
    return AlertDialog(
      key: const Key('new-api-key-dialog'),
      title: Text('Your key "${made.info.name}"'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Copy the key now. It is shown only this once. If you lose '
                'it, revoke it and make a new one.',
                key: const Key('api-key-once-note'),
                style: text.bodyMedium?.copyWith(color: scheme.error),
              ),
              const SizedBox(height: Space.md),
              block(const Key('new-api-key'), 'API key', made.key,
                  const Key('copy-api-key')),
              const SizedBox(height: Space.md),
              block(const Key('claude-code-command'), 'Add it to Claude Code',
                  command, const Key('copy-claude-command')),
              const SizedBox(height: Space.md),
              block(const Key('mcp-config'), 'Settings for other MCP clients',
                  config, const Key('copy-mcp-config')),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
            key: const Key('api-key-done'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('I copied the key')),
      ],
    );
  }
}
