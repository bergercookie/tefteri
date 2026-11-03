/// Entry point of the tefteri client.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/auth_controller.dart';

/// Starts the app inside a Riverpod scope, resuming an earlier session.
void main() {
  final container = ProviderContainer();
  container.read(authControllerProvider.notifier).restore();
  runApp(UncontrolledProviderScope(
    container: container,
    child: const TefteriApp(),
  ));
}
