/// Root widget and routing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/auth_controller.dart';
import 'core/shortcuts/app_shortcuts.dart';
import 'features/admin/users_screen.dart';
import 'features/auth/change_password_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/planner/planner_screen.dart';
import 'features/conflicts/conflicts_screen.dart';
import 'features/daily/daily_screen.dart';
import 'features/goals/goals_screen.dart';
import 'features/month/month_screen.dart';
import 'features/notes/note_editor_screen.dart';
import 'features/notes/notes_screen.dart';
import 'features/review/plan_history_screen.dart';
import 'features/review/review_screen.dart';
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
      final auth = ref.read(authControllerProvider);
      // Stay on the requested page (for example after a reload) until the
      // session check ends.
      if (auth.restoring) return null;
      final signedIn = auth.signedIn;
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
      GoRoute(path: '/notes', builder: (_, __) => const NotesScreen()),
      GoRoute(
        path: '/notes/new',
        builder: (_, s) => NoteEditorScreen(
          taskId: s.uri.queryParameters['task'],
          kind: s.uri.queryParameters['kind'] ?? 'custom',
        ),
      ),
      GoRoute(
        path: '/notes/:noteId',
        builder: (_, s) => NoteEditorScreen(
            key: ValueKey(s.pathParameters['noteId']),
            noteId: s.pathParameters['noteId']),
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
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      routerConfig: router,
      // Screens load data as soon as they are built, so wait for the session
      // check instead of sending requests that would fail.
      builder: (_, child) => restoring
          ? const Scaffold(
              key: Key('restoring-session'),
              body: Center(child: CircularProgressIndicator()),
            )
          : AppShortcuts(router: router, child: child ?? const SizedBox()),
    );
  }
}
