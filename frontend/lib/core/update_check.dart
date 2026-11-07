/// Tells whether a newer version of the app is published.
///
/// Standard releases are the GitHub releases tagged `vX.Y.Z`. Nightly builds
/// are the rolling `nightly` pre-release, titled `Nightly X.Y.Z.<hash>.postN`:
/// the app built from it has build name `X.Y.Z` and build number `N`.
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
      {required this.name,
      required this.post,
      required this.url,
      required this.label});

  /// Version name, for example `1.5.0`.
  final String name;

  /// Nightly post number, or null for a standard release.
  final int? post;

  /// Page of the release.
  final String url;

  /// Text for the user, for example `1.5.0` or `1.4.0 nightly 3`.
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
      name: tag, post: null, url: '${json['html_url'] ?? ''}', label: tag);
}

/// Reads the nightly release (`releases/tags/nightly`).
PublishedRelease? parseNightlyRelease(Map<String, dynamic> json) {
  final m = RegExp(r'(\d+\.\d+\.\d+)\.[0-9a-f]+\.post(\d+)')
      .firstMatch('${json['name'] ?? ''}');
  if (m == null) return null;
  return PublishedRelease(
      name: m[1]!,
      post: int.parse(m[2]!),
      url: '${json['html_url'] ?? ''}',
      label: '${m[1]} nightly ${m[2]}');
}

/// Compares the installed app with [latest] on [channel].
///
/// Standard: newer when the published version is above the installed one.
/// Nightly: newer when (version, post number) is above (installed version,
/// installed build number). An installed standard release has a build number
/// that counts commits, so it is never older than a nightly of its own version.
UpdateResult compareWithLatest(
    AppVersion installed, PublishedRelease latest, UpdateChannel channel) {
  final have = parseVersion(installed.name);
  final want = parseVersion(latest.name);
  if (have == null || want == null) {
    return UpdateResult(UpdateStatus.upToDate, latest);
  }
  var cmp = compareVersions(want, have);
  if (cmp == 0 && channel == UpdateChannel.nightly) {
    cmp = (latest.post ?? 0).compareTo(installed.build);
  }
  return UpdateResult(
      cmp > 0 ? UpdateStatus.available : UpdateStatus.upToDate, latest);
}

/// Fetches the latest release of [channel]. Tests override [releaseFetcherProvider].
typedef ReleaseFetcher = Future<PublishedRelease> Function(UpdateChannel);

/// Asks GitHub for the latest release of a channel.
final releaseFetcherProvider = Provider<ReleaseFetcher>((_) => (channel) async {
      final dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          headers: {'Accept': 'application/vnd.github+json'}));
      final path = channel == UpdateChannel.nightly ? 'tags/nightly' : 'latest';
      final r = await dio.get<Object?>('$_releasesApi/$path');
      final json = r.data! as Map<String, dynamic>;
      final release = channel == UpdateChannel.nightly
          ? parseNightlyRelease(json)
          : parseStableRelease(json);
      if (release == null) throw StateError('Unknown release format');
      return release;
    });

/// Checks the installed app against the chosen channel.
Future<UpdateResult> checkForUpdate(WidgetRef ref) async {
  final channel = ref.read(updateChannelProvider);
  final installed = await ref.read(appVersionProvider.future);
  final latest = await ref.read(releaseFetcherProvider)(channel);
  return compareWithLatest(installed, latest, channel);
}
