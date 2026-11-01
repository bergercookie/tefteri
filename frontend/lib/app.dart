/// Root widget and routing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/auth_controller.dart';
import 'core/shell.dart';
import 'features/auth/login_screen.dart';
import 'features/settings/connections_screen.dart';

/// Builds the router; redirects to `/login` while signed out.
GoRouter buildRouter(Ref ref) {
  final auth = ref.read(authControllerProvider.notifier);
  return GoRouter(
    initialLocation: '/',
    refreshListenable: auth,
    redirect: (context, state) {
      final signedIn = ref.read(authControllerProvider).signedIn;
      final atLogin = state.matchedLocation == '/login';
      if (!signedIn) return atLogin ? null : '/login';
      return atLogin ? '/' : null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(
        path: '/settings',
        builder: (_, __) => const ConnectionsScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (_, __) => const AppShell(
          title: 'Today',
          body: Center(child: Text('Daily view coming soon')),
        ),
      ),
    ],
  );
}

/// Provides the app router.
final routerProvider = Provider<GoRouter>(buildRouter);

/// The tefteri application.
class TefteriApp extends ConsumerWidget {
  /// Creates the app.
  const TefteriApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Tefteri',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
