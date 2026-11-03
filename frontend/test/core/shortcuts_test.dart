import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tefteri/app.dart';
import 'package:tefteri/core/auth_controller.dart';
import 'package:tefteri/core/context_filter.dart';
import 'package:tefteri/core/shortcuts/app_shortcuts.dart';
import 'package:tefteri/core/shortcuts/keymap.dart';
import 'package:tefteri/features/settings/sync_controller.dart';

class _FakeAuth extends AuthController {
  _FakeAuth(super.ref, {required bool signedIn}) {
    state = AuthState(signedIn: signedIn);
  }
}

class _FakeSync extends SyncController {
  _FakeSync(super.ref);

  int calls = 0;

  @override
  Future<void> syncAll() async => calls++;
}

final _viewsWithKeys = appViews.where((v) => v.key != null).toList();

/// A stub page per view, each with a text field.
Widget _page(String path) => Scaffold(
      body: Column(
        children: [
          Text('page:$path'),
          TextField(key: Key('field-$path')),
        ],
      ),
    );

late _FakeSync _sync;

Future<(GoRouter, ProviderContainer)> _pump(WidgetTester tester,
    {bool signedIn = true}) async {
  final router = GoRouter(initialLocation: '/', routes: [
    for (final v in appViews)
      GoRoute(path: v.path, builder: (_, __) => _page(v.path)),
  ]);
  final container = ProviderContainer(overrides: [
    authControllerProvider
        .overrideWith((ref) => _FakeAuth(ref, signedIn: signedIn)),
    syncControllerProvider.overrideWith((ref) => _sync = _FakeSync(ref)),
  ]);
  addTearDown(container.dispose);
  container.read(syncControllerProvider); // creates this test's _sync
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppShortcuts(router: router, child: child!),
    ),
  ));
  await tester.pumpAndSettle();
  return (router, container);
}

Future<void> _press(WidgetTester tester, String character) async {
  final key = switch (character) {
    '?' => LogicalKeyboardKey.slash,
    '1' => LogicalKeyboardKey.digit1,
    '2' => LogicalKeyboardKey.digit2,
    '3' => LogicalKeyboardKey.digit3,
    _ => LogicalKeyboardKey(LogicalKeyboardKey.keyA.keyId +
        character.codeUnitAt(0) -
        'a'.codeUnitAt(0)),
  };
  await tester.sendKeyEvent(key, character: character);
  await tester.pumpAndSettle();
}

void main() {
  test('the keymap has one unique key for each view', () {
    final keys = [for (final s in appShortcuts) s.keys];
    expect(keys.toSet(), hasLength(keys.length));
    for (final v in appViews
        .where((v) => v.path != '/password' && v.path != '/settings')) {
      expect(v.key, isNotNull, reason: '${v.label} needs a shortcut');
    }
    for (final label in [
      'Today',
      'Week',
      'Month',
      'Year',
      'Goals',
      'Reviews',
      'Notes',
      'Connections',
    ]) {
      expect(appViews.map((v) => v.label), contains(label));
    }
  });

  test('the app router has a route for every view of the keymap', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final paths = {
      for (final r in container.read(routerProvider).configuration.routes)
        if (r is GoRoute) r.path,
    };
    for (final v in appViews) {
      expect(paths, contains(v.path));
    }
  });

  testWidgets('each shortcut opens its view from every other view',
      (tester) async {
    final (router, _) = await _pump(tester);
    for (final from in _viewsWithKeys) {
      for (final to in _viewsWithKeys) {
        if (from == to) continue;
        router.go(from.path);
        await tester.pumpAndSettle();
        await _press(tester, to.key!);
        expect(find.text('page:${to.path}'), findsOneWidget,
            reason: '${to.key} from ${from.path}');
      }
    }
  });

  testWidgets('plain keys go into a focused text field', (tester) async {
    final (router, container) = await _pump(tester);
    router.go('/week');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('field-/week')));
    await tester.pump();
    for (final c in ['m', 'n', '2', '?']) {
      await _press(tester, c);
    }
    expect(find.text('page:/week'), findsOneWidget);
    expect(container.read(contextFilterProvider), ContextFilter.all);
    expect(find.byKey(const Key('shortcut-help')), findsNothing);

    // Esc leaves the field; then the same key opens the view.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await _press(tester, 'm');
    expect(find.text('page:/month'), findsOneWidget);
  });

  testWidgets('digits switch the work/life filter', (tester) async {
    final (_, container) = await _pump(tester);
    await _press(tester, '3');
    expect(container.read(contextFilterProvider), ContextFilter.work);
    await _press(tester, '2');
    expect(container.read(contextFilterProvider), ContextFilter.life);
    await _press(tester, '1');
    expect(container.read(contextFilterProvider), ContextFilter.all);
  });

  testWidgets('S syncs and does not open Connections', (tester) async {
    final (router, _) = await _pump(tester);
    router.go('/week');
    await tester.pumpAndSettle();
    await _press(tester, 's');
    expect(_sync.calls, 1);
    expect(find.text('page:/week'), findsOneWidget);
    // While typing, s is a letter in the field.
    await tester.tap(find.byKey(const Key('field-/week')));
    await tester.pump();
    await _press(tester, 's');
    expect(_sync.calls, 1);
  });

  testWidgets('F5 syncs, also while typing', (tester) async {
    await _pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pumpAndSettle();
    expect(_sync.calls, 1);
    await tester.tap(find.byKey(const Key('field-/')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pumpAndSettle();
    expect(_sync.calls, 2);
  });

  testWidgets('? opens the help overlay that lists every shortcut',
      (tester) async {
    await _pump(tester);
    await _press(tester, '?');
    expect(find.byKey(const Key('shortcut-help')), findsOneWidget);
    for (final s in appShortcuts) {
      expect(find.byKey(Key('shortcut-${s.keys}')), findsOneWidget);
      expect(find.text(s.description), findsOneWidget);
    }
    // View keys do nothing while the overlay is open.
    await _press(tester, 'w');
    expect(find.byKey(const Key('shortcut-help')), findsOneWidget);
    await tester.tap(find.byKey(const Key('shortcut-help-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shortcut-help')), findsNothing);
    expect(find.text('page:/'), findsOneWidget);
  });

  testWidgets('shortcuts do nothing while signed out', (tester) async {
    final (_, container) = await _pump(tester, signedIn: false);
    await _press(tester, 'w');
    await _press(tester, '3');
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pumpAndSettle();
    expect(find.text('page:/'), findsOneWidget);
    expect(container.read(contextFilterProvider), ContextFilter.all);
    expect(_sync.calls, 0);
  });
}
