/// Entry point of the tefteri client.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

/// Starts the app inside a Riverpod scope.
void main() {
  runApp(const ProviderScope(child: TefteriApp()));
}
