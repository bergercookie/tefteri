/// Entry point of the tefteri client.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/api_client.dart';
import 'core/auth_controller.dart';
import 'core/server_address.dart';

/// Starts the app inside a Riverpod scope, with the saved server address,
/// resuming an earlier session.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final server = await ServerAddress.load();
  // The token of an earlier run: Android can end the app's process while it is
  // in the background, and the user must not have to sign in again.
  final token = await TokenStore.load();
  final container = ProviderContainer(overrides: [
    serverAddressProvider.overrideWith((_) => ServerAddress(server)),
    tokenStoreProvider.overrideWith((_) => TokenStore(token, !kIsWeb)),
  ]);
  container.read(authControllerProvider.notifier).restore();
  runApp(UncontrolledProviderScope(
    container: container,
    child: const TefteriApp(),
  ));
}
