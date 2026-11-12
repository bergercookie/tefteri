/// The push token of automatic key results (FR-010). The token is shown
/// once, right after it is made; later only its last characters show.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/planning_models.dart';
import '../../theme/theme.dart';
import 'annual_api.dart';
import 'annual_controller.dart';

/// Opens the token dialog.
Future<void> showPushTokenDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const PushTokenDialog());

/// The token dialog.
class PushTokenDialog extends ConsumerStatefulWidget {
  /// Creates the dialog.
  const PushTokenDialog({super.key});

  @override
  ConsumerState<PushTokenDialog> createState() => _PushTokenDialogState();
}

class _PushTokenDialogState extends ConsumerState<PushTokenDialog> {
  String? _token;
  String? _error;
  bool _busy = false;
  bool _copied = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() => _run(() async {
        final made = await ref.read(annualApiProvider).createPushToken();
        ref.invalidate(pushTokenProvider);
        if (mounted) {
          setState(() {
            _token = made.token;
            _copied = false;
          });
        }
      });

  Future<void> _delete() => _run(() async {
        await ref.read(annualApiProvider).deletePushToken();
        ref.invalidate(pushTokenProvider);
        if (mounted) setState(() => _token = null);
      });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final info = ref.watch(pushTokenProvider);
    final token = _token;
    return AlertDialog(
      key: const Key('push-token-dialog'),
      title: const Text('Push token'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
                'An outside source uses this token to send values to your '
                'automatic key results. It works only for that.'),
            const SizedBox(height: Space.md),
            if (token != null) ...[
              Container(
                padding: const EdgeInsets.all(Space.md),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainer,
                  border: Border.all(color: context.tefteri.rule),
                  borderRadius: BorderRadius.circular(Corner.md),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(token,
                          key: const Key('push-token-value'),
                          style: text.bodyMedium),
                    ),
                    IconButton(
                      key: const Key('push-token-copy'),
                      tooltip: 'Copy the token',
                      icon: Icon(_copied ? Icons.check : Icons.copy),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: token));
                        if (mounted) setState(() => _copied = true);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Space.sm),
              Text(
                'Copy the token now. Tefteri shows it only once. Anyone with '
                'the token can send values to your automatic key results.',
                key: const Key('push-token-warning'),
                style: text.bodySmall?.copyWith(color: scheme.error),
              ),
            ] else
              info.when(
                loading: () => const SizedBox(height: 48, child: Loading()),
                error: (e, _) => Text(apiErrorMessage(e)),
                data: (i) => Text(
                  i.exists
                      ? 'A token ending in ${i.hint ?? '…'} exists'
                          '${i.createdAt == null ? '' : ', made ${dateKey(i.createdAt!.toLocal())}'}'
                          '${i.lastUsedAt == null ? '. It was never used.' : ', last used ${dateKey(i.lastUsedAt!.toLocal())}.'}'
                      : 'No token yet.',
                  key: const Key('push-token-hint'),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: Space.sm),
                child: Text(_error!, style: TextStyle(color: scheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        if (token == null && (info.valueOrNull?.exists ?? false))
          TextButton(
            key: const Key('push-token-delete'),
            onPressed: _busy ? null : _delete,
            child: const Text('Remove token'),
          ),
        if (token == null)
          OutlinedButton(
            key: const Key('push-token-create'),
            onPressed: _busy ? null : _create,
            child: Text((info.valueOrNull?.exists ?? false)
                ? 'Make a new token (the old one stops)'
                : 'Make a token'),
          ),
        FilledButton(
          key: const Key('push-token-close'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
