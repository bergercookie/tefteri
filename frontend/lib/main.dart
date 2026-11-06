/// Entry point of the tefteri client.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/auth_controller.dart';
import 'core/server_address.dart';

/// Starts the app inside a Riverpod scope, with the saved server address,
/// resuming an earlier session.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final server = await ServerAddress.load();
  final container = ProviderContainer(overrides: [
    serverAddressProvider.overrideWith((_) => ServerAddress(server)),
  ]);
  container.read(authControllerProvider.notifier).restore();
  runApp(UncontrolledProviderScope(
    container: container,
    child: const TefteriApp(),
  ));
}
