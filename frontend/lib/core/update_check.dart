/// Tells whether a newer version of the app is published.
///
/// Every push to the main branch is a GitHub release tagged `vX.Y.Z`, and the latest of them is
/// the one that the app compares itself with.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'versions.dart';

const _releasesApi =
    'https://api.github.com/repos/bergercookie/tefteri/releases';

/// A published release.
class PublishedRelease {
  /// Creates a release.
  const PublishedRelease(
      {required this.name, required this.url, required this.label});

  /// Version name, for example `1.5.0`.
  final String name;

  /// Page of the release.
  final String url;

  /// Text for the user, for example `1.5.0`.
  final String label;
}

/// What the check found.
enum UpdateStatus {
  /// The installed version is the latest.
  upToDate,

  /// A newer version is published.
  available,
}

/// Outcome of a check.
class UpdateResult {
  /// Creates a result.
  const UpdateResult(this.status, this.latest);

  /// Whether to update.
  final UpdateStatus status;

  /// The latest release on the chosen channel.
  final PublishedRelease latest;
}

/// Splits `1.4.0` into numbers; null when it is not of that form.
List<int>? parseVersion(String text) {
  final m = RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(text.trim());
  return m == null ? null : [for (var i = 1; i <= 3; i++) int.parse(m[i]!)];
}

/// Compares two parsed versions: negative when [a] is older.
int compareVersions(List<int> a, List<int> b) {
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i].compareTo(b[i]);
  }
  return 0;
}

/// Reads the latest standard release from a `releases/latest` answer.
PublishedRelease? parseStableRelease(Map<String, dynamic> json) {
  final tag = '${json['tag_name'] ?? ''}'.replaceFirst(RegExp('^v'), '');
  if (parseVersion(tag) == null) return null;
  return PublishedRelease(
      name: tag, url: '${json['html_url'] ?? ''}', label: tag);
}

/// Compares the installed app with [latest]: newer when the published version is above the
/// installed one.
UpdateResult compareWithLatest(AppVersion installed, PublishedRelease latest) {
  final have = parseVersion(installed.name);
  final want = parseVersion(latest.name);
  if (have == null || want == null) {
    return UpdateResult(UpdateStatus.upToDate, latest);
  }
  return UpdateResult(
      compareVersions(want, have) > 0
          ? UpdateStatus.available
          : UpdateStatus.upToDate,
      latest);
}

/// Fetches the latest release. Tests override [releaseFetcherProvider].
typedef ReleaseFetcher = Future<PublishedRelease> Function();

/// Asks GitHub for the latest release.
final releaseFetcherProvider = Provider<ReleaseFetcher>((_) => () async {
      final dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          headers: {'Accept': 'application/vnd.github+json'}));
      final r = await dio.get<Object?>('$_releasesApi/latest');
      final release = parseStableRelease(r.data! as Map<String, dynamic>);
      if (release == null) throw StateError('Unknown release format');
      return release;
    });

/// Checks the installed app against the latest release.
Future<UpdateResult> checkForUpdate(WidgetRef ref) async {
  final installed = await ref.read(appVersionProvider.future);
  final latest = await ref.read(releaseFetcherProvider)();
  return compareWithLatest(installed, latest);
}
