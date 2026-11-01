/// Root widget and routing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/auth_controller.dart';
import 'features/admin/users_screen.dart';
import 'features/auth/change_password_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/calendar/calendar_screen.dart';
import 'features/conflicts/conflicts_screen.dart';
import 'features/daily/daily_screen.dart';
import 'features/goals/goals_screen.dart';
import 'features/month/month_screen.dart';
import 'features/settings/connections_screen.dart';
import 'features/week/week_screen.dart';
import 'features/year/year_screen.dart';

/// Notifies the router whenever the sign-in state changes.
final authRefreshProvider = Provider<Listenable>((ref) {
  final notifier = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, __) => notifier.value++);
  ref.onDispose(notifier.dispose);
  return notifier;
});

/// Builds the router; redirects to `/login` while signed out.
GoRouter buildRouter(Ref ref) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: ref.read(authRefreshProvider),
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
      GoRoute(path: '/users', builder: (_, __) => const UsersScreen()),
      GoRoute(
        path: '/password',
        builder: (_, __) => const ChangePasswordScreen(),
      ),
      GoRoute(path: '/', builder: (_, __) => const DailyScreen()),
      GoRoute(path: '/calendar', builder: (_, __) => const CalendarScreen()),
      GoRoute(path: '/week', builder: (_, __) => const WeekScreen()),
      GoRoute(path: '/month', builder: (_, __) => const MonthScreen()),
      GoRoute(path: '/year', builder: (_, __) => const YearScreen()),
      GoRoute(path: '/goals', builder: (_, __) => const GoalsScreen()),
      GoRoute(
        path: '/conflicts',
        builder: (_, __) => const ConflictsScreen(),
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
