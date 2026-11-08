/// The server the native clients (Android, Linux packages) talk to.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _apiOverride = String.fromEnvironment('TEFTERI_API');
const _prefsKey = 'server_address';

/// Turns what a person typed into a server address such as
/// `https://tefteri.example.com`, or null when it is empty or not a web
/// address. A missing scheme means `https://`; a trailing slash or `/api/v1`
/// is dropped.
String? normalizeServerAddress(String input) {
  var s = input.trim();
  if (s.isEmpty) return null;
  if (!s.contains('://')) s = 'https://$s';
  final uri = Uri.tryParse(s);
  if (uri == null ||
      !(uri.scheme == 'http' || uri.scheme == 'https') ||
      uri.host.isEmpty) {
    return null;
  }
  s = s.replaceAll(RegExp(r'/+$'), '');
  if (s.endsWith('/api/v1')) s = s.substring(0, s.length - '/api/v1'.length);
  return s.replaceAll(RegExp(r'/+$'), '');
}

/// The saved server address (null until one is set).
class ServerAddress extends StateNotifier<String?> {
  /// Creates the store holding [initial].
  ServerAddress([super.initial]);

  /// Reads the address saved by an earlier run.
  static Future<String?> load() async =>
      (await SharedPreferences.getInstance()).getString(_prefsKey);

  /// Remembers [address] for this run and the next ones.
  Future<void> set(String address) async {
    state = address;
    await (await SharedPreferences.getInstance()).setString(_prefsKey, address);
  }
}

/// Provides the saved server address; `main()` overrides it with the stored value.
final serverAddressProvider =
    StateNotifierProvider<ServerAddress, String?>((_) => ServerAddress());

/// True when the user has to say where the server is: every client except the
/// web one, which talks to the server it was loaded from.
bool get needsServerAddress => !kIsWeb && _apiOverride.isEmpty;

/// Base URL of the backend API. The web client uses the server it was loaded
/// from; a build with `--dart-define=TEFTERI_API=https://host/api/v1` uses
/// that; the others use the address entered on the login screen.
final apiBaseUrlProvider = Provider<String>((ref) {
  if (_apiOverride.isNotEmpty) return _apiOverride;
  if (kIsWeb) return Uri.base.resolve('api/v1').toString();
  final server = ref.watch(serverAddressProvider);
  return '${server ?? 'http://localhost:8000'}/api/v1';
});
