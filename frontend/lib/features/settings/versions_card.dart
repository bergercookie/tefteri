/// Settings card for the Android and Linux apps: show the backend and
/// application versions, choose a release channel and check for updates.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/open_url.dart';
import '../../core/server_address.dart';
import '../../core/update_check.dart';
import '../../core/versions.dart';
import '../../theme/theme.dart';

/// True for the clients that are installed (Android and Linux), which can be
/// out of date. The web client is always as new as its server.
bool get isInstalledClient =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.linux);

/// The card. Callers show it only when [isInstalledClient] is true.
class VersionsCard extends ConsumerStatefulWidget {
  /// Creates the card.
  const VersionsCard({super.key});

  @override
  ConsumerState<VersionsCard> createState() => _VersionsCardState();
}

class _VersionsCardState extends ConsumerState<VersionsCard> {
  bool _checking = false;
  UpdateResult? _result;
  String? _error;

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await checkForUpdate(ref);
      if (mounted) setState(() => _result = result);
    } on Object catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final show = ref.watch(showVersionsProvider);
    final channel = ref.watch(updateChannelProvider);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: const Key('versions-card'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              key: const Key('show-versions-switch'),
              title: const Text('Show versions'),
              subtitle: const Text('The backend and the application version.'),
              value: show,
              onChanged: (v) => ref.read(showVersionsProvider.notifier).set(v),
            ),
            if (show) ...[
              _versionRow(
                  'Backend version',
                  'backend-version',
                  ref
                      .watch(serverVersionProvider(
                          ref.watch(serverAddressProvider)))
                      .when(
                        data: (v) => v,
                        loading: () => 'Checking...',
                        error: (_, __) => 'Unknown (cannot reach the server)',
                      )),
              _versionRow(
                  'Application version',
                  'app-version',
                  ref.watch(appVersionProvider).when(
                        data: (v) => '$v',
                        loading: () => 'Checking...',
                        error: (_, __) => 'Unknown',
                      )),
            ],
            const Divider(),
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, 0),
              child: Text('Updates', style: text.titleSmall),
            ),
            Padding(
              padding: const EdgeInsets.all(Space.lg),
              child: SegmentedButton<UpdateChannel>(
                key: const Key('update-channel'),
                segments: const [
                  ButtonSegment(
                      value: UpdateChannel.standard, label: Text('Standard')),
                  ButtonSegment(
                      value: UpdateChannel.nightly, label: Text('Nightly')),
                ],
                selected: {channel},
                onSelectionChanged: (s) {
                  ref.read(updateChannelProvider.notifier).set(s.first);
                  setState(() {
                    _result = null;
                    _error = null;
                  });
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonal(
                  key: const Key('check-updates'),
                  onPressed: _checking ? null : _check,
                  child: Text(_checking ? 'Checking...' : 'Check for updates'),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
                child: Text(_error!,
                    key: const Key('update-error'),
                    style: text.bodyMedium?.copyWith(color: scheme.error)),
              ),
            if (_result != null) _resultView(_result!, text),
          ],
        ),
      ),
    );
  }

  Widget _versionRow(String label, String key, String value) => ListTile(
        dense: true,
        title: Text(label),
        trailing: Text(value, key: Key(key)),
      );

  Widget _resultView(UpdateResult r, TextTheme text) {
    final newer = r.status == UpdateStatus.available;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              newer
                  ? 'A newer version is available: ${r.latest.label}.'
                  : 'You have the latest version (${r.latest.label}).',
              key: const Key('update-result'),
              style: text.bodyMedium,
            ),
          ),
          if (newer && r.latest.url.isNotEmpty)
            TextButton(
              key: const Key('update-open'),
              onPressed: () =>
                  ref.read(openUrlProvider)(Uri.parse(r.latest.url)),
              child: const Text('Download'),
            ),
        ],
      ),
    );
  }
}
