/// The Android app that matches the server: the link that adds it to
/// Obtainium, and the QR code of the link.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';

/// What the server says about installing the Android app.
@immutable
class AndroidAppInfo {
  /// Creates the info.
  const AndroidAppInfo({
    required this.version,
    required this.available,
    this.releaseUrl,
    this.obtainiumLink,
    this.qr = const [],
  });

  /// Parses the answer of `GET /me/android-app`.
  factory AndroidAppInfo.fromJson(Map<String, dynamic> j) => AndroidAppInfo(
        version: '${j['version']}',
        available: j['available'] == true,
        releaseUrl: j['release_url'] as String?,
        obtainiumLink: j['obtainium_link'] as String?,
        qr: [for (final row in (j['qr'] as List? ?? const [])) '$row'],
      );

  /// The version of the server.
  final String version;

  /// False when the server is not a published build: no release matches it.
  final bool available;

  /// The GitHub page of the release that holds the app.
  final String? releaseUrl;

  /// The link that adds the app to Obtainium.
  final String? obtainiumLink;

  /// The QR code of [obtainiumLink]: a row of `0` and `1` for each line.
  final List<String> qr;
}

/// The Android app of the version that the server runs.
final androidAppProvider =
    FutureProvider.autoDispose<AndroidAppInfo>((ref) async {
  final r = await ref.watch(dioProvider).get<Object?>('/me/android-app');
  return AndroidAppInfo.fromJson(r.data! as Map<String, dynamic>);
});
