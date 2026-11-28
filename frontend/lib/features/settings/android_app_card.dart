/// Settings card: install the Android app of the server's version with
/// Obtainium, so that the app is updated together with the server.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/open_url.dart';
import '../../theme/theme.dart';
import 'android_app.dart';

/// Shows a link and a QR code that add the Android app to Obtainium, pinned
/// to the release of the version that the server runs. Scan the code with the
/// phone, or open the link on it; after a server update, use the new link.
class AndroidAppCard extends ConsumerWidget {
  /// Creates the card.
  const AndroidAppCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final info = ref.watch(androidAppProvider);
    return Card(
      key: const Key('android-app-card'),
      margin: const EdgeInsets.only(top: Space.lg),
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Android app', style: text.titleMedium),
            const SizedBox(height: Space.xs),
            Text(
              'Obtainium installs the Android app from the GitHub release of '
              'the version that this server runs, and updates it when you '
              'follow a server update with the new link. Open the link on '
              'the phone, or scan the code with it.',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: Space.md),
            info.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(Space.md),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text(apiErrorMessage(e),
                  key: const Key('android-app-error'),
                  style: TextStyle(color: scheme.error)),
              data: (i) => _Body(info: i),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.info});

  final AndroidAppInfo info;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final link = info.obtainiumLink;
    if (!info.available || link == null) {
      return Text(
        'This server (version ${info.version}) is not a published release, '
        'so there is no matching Android app to install.',
        key: const Key('android-app-unavailable'),
        style: text.bodyMedium,
      );
    }
    final onAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Server version ${info.version}',
            key: const Key('android-app-version'), style: text.titleSmall),
        const SizedBox(height: Space.md),
        Center(child: QrCode(key: const Key('android-app-qr'), rows: info.qr)),
        const SizedBox(height: Space.md),
        SelectableText(link,
            key: const Key('android-app-link'),
            maxLines: 3,
            style: text.bodySmall),
        const SizedBox(height: Space.sm),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            if (onAndroid)
              FilledButton.icon(
                key: const Key('open-in-obtainium'),
                icon: const Icon(Icons.system_update_alt),
                label: const Text('Open in Obtainium'),
                onPressed: () => _open(context, ref, link),
              ),
            OutlinedButton.icon(
              key: const Key('copy-obtainium-link'),
              icon: const Icon(Icons.copy),
              label: const Text('Copy the link'),
              onPressed: () => _copy(context, link),
            ),
            if (info.releaseUrl != null)
              TextButton.icon(
                key: const Key('open-release'),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Release page'),
                onPressed: () => _open(context, ref, info.releaseUrl!),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _copy(BuildContext context, String link) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: link));
    messenger
        .showSnackBar(const SnackBar(content: Text('The link is copied.')));
  }

  Future<void> _open(BuildContext context, WidgetRef ref, String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ref.read(openUrlProvider)(Uri.parse(url));
    if (!ok) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Nothing could open the link.')));
    }
  }
}

/// A QR code. It is always dark on light, whatever the theme: scanners expect
/// that, and many fail on an inverted code.
class QrCode extends StatelessWidget {
  /// Creates a code from [rows]: one string of `0` and `1` per line.
  const QrCode({super.key, required this.rows, this.size = 220});

  /// The modules, a row of `0` and `1` for each line.
  final List<String> rows;

  /// The width and height, with the quiet zone.
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'QR code of the link',
      image: true,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _QrPainter(
            rows,
            paper: TefteriColors.light.paper,
            ink: tefteriScheme(Brightness.light).onSurface,
          ),
        ),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.rows, {required this.paper, required this.ink});

  final List<String> rows;
  final Color paper;
  final Color ink;

  /// Empty modules around the code, as the QR standard asks.
  static const _quiet = 2;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = paper);
    if (rows.isEmpty) return;
    final n = rows.length + 2 * _quiet;
    final cell = size.width / n;
    final paint = Paint()..color = ink;
    for (var y = 0; y < rows.length; y++) {
      for (var x = 0; x < rows[y].length; x++) {
        if (rows[y][x] != '1') continue;
        // Slightly larger than the cell, so that no seam shows between two.
        canvas.drawRect(
            Rect.fromLTWH(
                (x + _quiet) * cell, (y + _quiet) * cell, cell + 0.5, cell + 0.5),
            paint);
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) =>
      old.rows != rows || old.paper != paper || old.ink != ink;
}
