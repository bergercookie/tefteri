/// Root widget and routing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/app_selection.dart';
import 'core/auth_controller.dart';
import 'core/shortcuts/app_shortcuts.dart';
import 'theme/theme.dart';
import 'features/admin/admin_settings_screen.dart';
import 'features/admin/users_screen.dart';
import 'features/auth/change_password_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/planner/planner_screen.dart';
import 'features/conflicts/conflicts_screen.dart';
import 'features/daily/daily_screen.dart';
import 'features/goals/goals_screen.dart';
import 'features/month/month_screen.dart';
import 'features/review/plan_history_screen.dart';
import 'features/review/review_screen.dart';
import 'features/settings/connections_screen.dart';
import 'features/settings/settings_screen.dart';
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
      final auth = ref.read(authControllerProvider);
      // Stay on the requested page (for example after a reload) until the
      // session check ends.
      if (auth.restoring) return null;
      final signedIn = auth.signedIn;
      final atLogin = state.matchedLocation == '/login';
      if (!signedIn) return atLogin ? null : '/login';
      if (atLogin) return '/';
      // Admin settings are for administrators; the server checks the rights too.
      final admin = ref.read(authControllerProvider).isAdmin;
      final adminPage = state.matchedLocation == '/admin' ||
          state.matchedLocation.startsWith('/admin/');
      if (adminPage && !admin) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(
        path: '/settings',
        builder: (_, __) => const SettingsScreen(),
        routes: [
          GoRoute(
            path: 'connections',
            builder: (_, __) => const ConnectionsScreen(),
          ),
          GoRoute(
            path: 'password',
            builder: (_, __) => const ChangePasswordScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/admin',
        builder: (_, __) => const AdminSettingsScreen(),
        routes: [
          GoRoute(path: 'users', builder: (_, __) => const UsersScreen()),
        ],
      ),
      // Old addresses, from before Settings and Admin settings existed.
      GoRoute(path: '/password', redirect: (_, __) => '/settings/password'),
      GoRoute(path: '/users', redirect: (_, __) => '/admin/users'),
      GoRoute(path: '/', builder: (_, __) => const PlannerScreen()),
      GoRoute(path: '/daily', builder: (_, __) => const DailyScreen()),
      GoRoute(path: '/calendar', redirect: (_, __) => '/'),
      GoRoute(path: '/week', builder: (_, __) => const WeekScreen()),
      GoRoute(path: '/month', builder: (_, __) => const MonthScreen()),
      GoRoute(path: '/year', builder: (_, __) => const YearScreen()),
      GoRoute(path: '/goals', builder: (_, __) => const GoalsScreen()),
      GoRoute(
        path: '/conflicts',
        builder: (_, __) => const ConflictsScreen(),
      ),
      GoRoute(path: '/review', builder: (_, __) => const PlanHistoryScreen()),
      GoRoute(
        path: '/review/:planId',
        builder: (_, s) => ReviewScreen(planId: s.pathParameters['planId']!),
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
    final router = ref.watch(routerProvider);
    final restoring =
        ref.watch(authControllerProvider.select((s) => s.restoring));
    return MaterialApp.router(
      title: 'Tefteri',
      theme: tefteriLight,
      darkTheme: tefteriDark,
      themeMode: ThemeMode.system,
      routerConfig: router,
      // Screens load data as soon as they are built, so wait for the session
      // check instead of sending requests that would fail.
      builder: (_, child) => restoring
          ? const Scaffold(
              key: Key('restoring-session'),
              body: Loading(),
            )
          : AppShortcuts(
              router: router,
              // One selection area for the whole app, so the user can select
              // and copy text on every screen, also in dialogs and messages.
              child: AppSelection(child: child ?? const SizedBox()),
            ),
    );
  }
}
