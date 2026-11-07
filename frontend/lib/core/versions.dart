/// The versions of the app and of the server, and what the user chose to
/// show of them.
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The version of this app: the build name (`1.4.0`) and build number.
class AppVersion {
  /// Creates a version.
  const AppVersion(this.name, this.build);

  /// Build name, for example `1.4.0`.
  final String name;

  /// Build number; 0 when unknown.
  final int build;

  /// Text for the user: `1.4.0 (build 3)`.
  @override
  String toString() => '$name (build $build)';
}

/// Reads the version of the running app. Tests override it.
final appVersionProvider = FutureProvider<AppVersion>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return AppVersion(info.version, int.tryParse(info.buildNumber) ?? 0);
});

/// Asks a server for its version (`GET /version`, which needs no login).
///
/// [address] is a server address such as `https://tefteri.example.com`; null
/// means the server the web client was loaded from. Tests override this.
final serverVersionProvider =
    FutureProvider.autoDispose.family<String, String?>((ref, address) async {
  final url = address == null
      ? (kIsWeb ? Uri.base.resolve('version').toString() : '')
      : '$address/version';
  if (url.isEmpty) throw StateError('no server');
  final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 6)));
  final r = await dio.get<Object?>(url);
  final data = r.data;
  final version = data is Map ? data['version'] : null;
  if (version is! String) throw StateError('not a tefteri server');
  return version;
});

/// Which releases the update check follows.
enum UpdateChannel {
  /// Tagged releases.
  standard,

  /// The rolling `nightly` pre-release.
  nightly,
}

const _showVersionsKey = 'show_versions';
const _channelKey = 'update_channel';

/// Whether Settings shows the backend and application versions.
class ShowVersions extends StateNotifier<bool> {
  /// Starts with the saved choice (off until it is read).
  ShowVersions() : super(false) {
    SharedPreferences.getInstance().then((p) {
      if (mounted) state = p.getBool(_showVersionsKey) ?? false;
    }, onError: (_) {}); // no saved choice: keep the default
  }

  /// Sets and saves the choice.
  Future<void> set(bool value) async {
    state = value;
    await (await SharedPreferences.getInstance())
        .setBool(_showVersionsKey, value);
  }
}

/// The saved "show versions" choice.
final showVersionsProvider =
    StateNotifierProvider<ShowVersions, bool>((_) => ShowVersions());

/// The release channel of the update check.
class ChannelChoice extends StateNotifier<UpdateChannel> {
  /// Starts on the standard channel until the saved one is read.
  ChannelChoice() : super(UpdateChannel.standard) {
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      state = p.getString(_channelKey) == UpdateChannel.nightly.name
          ? UpdateChannel.nightly
          : UpdateChannel.standard;
    }, onError: (_) {}); // no saved choice: keep the default
  }

  /// Sets and saves the channel.
  Future<void> set(UpdateChannel value) async {
    state = value;
    await (await SharedPreferences.getInstance())
        .setString(_channelKey, value.name);
  }
}

/// The saved update channel.
final updateChannelProvider =
    StateNotifierProvider<ChannelChoice, UpdateChannel>((_) => ChannelChoice());
