/// Root widget and routing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/find.dart';
import 'core/app_selection.dart';
import 'core/auth_controller.dart';
import 'core/shortcuts/app_shortcuts.dart';
import 'theme/theme.dart';
import 'features/admin/admin_settings_screen.dart';
import 'features/annual/annual_screen.dart';
import 'features/annual_review/annual_review_screen.dart';
import 'features/admin/users_screen.dart';
import 'features/auth/change_password_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/planner/planner_screen.dart';
import 'features/conflicts/conflicts_screen.dart';
import 'features/daily/daily_screen.dart';
import 'features/month/month_screen.dart';
import 'features/month/review_screen.dart';
import 'features/projects/projects_screen.dart';
import 'features/review/plan_history_screen.dart';
import 'features/review/review_screen.dart';
import 'features/settings/checklists_screen.dart';
import 'features/settings/connections_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/statistics/drilldown_screen.dart';
import 'features/week/week_screen.dart';
import 'features/weekly/weekly_screen.dart';

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
            builder: (_, s) =>
                ConnectionsScreen(choose: s.uri.queryParameters['choose']),
          ),
          GoRoute(
            path: 'checklists',
            builder: (_, __) => const ChecklistsScreen(),
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
      GoRoute(
        path: '/',
        builder: (_, s) => PlannerScreen(
            initialDate:
                DateTime.tryParse(s.uri.queryParameters['date'] ?? '')),
      ),
      GoRoute(path: '/daily', builder: (_, __) => const DailyScreen()),
      GoRoute(path: '/calendar', redirect: (_, __) => '/'),
      GoRoute(
        path: '/week',
        builder: (_, s) => WeekScreen(
            initialDate:
                DateTime.tryParse(s.uri.queryParameters['date'] ?? '')),
        routes: [
          GoRoute(
            path: 'plan',
            builder: (_, s) => WeeklyPlanningScreen(
                initialDate:
                    DateTime.tryParse(s.uri.queryParameters['date'] ?? '')),
          ),
        ],
      ),
      GoRoute(
        path: '/month',
        builder: (_, s) => MonthScreen(
            initialDate:
                DateTime.tryParse(s.uri.queryParameters['date'] ?? '')),
        routes: [
          GoRoute(
            path: 'review',
            builder: (_, s) {
              final date =
                  DateTime.tryParse(s.uri.queryParameters['date'] ?? '') ??
                      DateTime.now();
              final month = '${date.year.toString().padLeft(4, '0')}-'
                  '${date.month.toString().padLeft(2, '0')}';
              return MonthReviewScreen(month: month);
            },
          ),
        ],
      ),
      GoRoute(
        path: '/year',
        builder: (_, s) => AnnualReviewScreen(
            initialYear:
                DateTime.tryParse(s.uri.queryParameters['date'] ?? '')?.year),
        routes: [
          GoRoute(
            path: ':year',
            builder: (_, s) => AnnualReviewScreen(
                initialYear: int.tryParse(s.pathParameters['year'] ?? '')),
          ),
        ],
      ),
      statisticsRoute(),
      GoRoute(
        path: '/annual',
        builder: (_, s) => AnnualScreen(
            initialYear: int.tryParse(s.uri.queryParameters['year'] ?? '') ??
                DateTime.tryParse(s.uri.queryParameters['date'] ?? '')?.year),
      ),
      // Goals live only in the annual plan now; old links still work.
      GoRoute(path: '/goals', redirect: (_, __) => '/annual'),
      GoRoute(path: '/projects', builder: (_, __) => const ProjectsScreen()),
      GoRoute(
        path: '/conflicts',
        builder: (_, __) => const ConflictsScreen(),
      ),
      GoRoute(
        path: '/review',
        builder: (_, s) => PlanHistoryScreen(
          period: s.uri.queryParameters['period'],
          year: int.tryParse(s.uri.queryParameters['year'] ?? ''),
        ),
      ),
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
              child: FindHost(
                child: AppSelection(child: child ?? const SizedBox()),
              ),
            ),
    );
  }
}
