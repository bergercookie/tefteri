import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tefteri/core/auth_controller.dart';
import 'package:tefteri/core/shortcuts/app_shortcuts.dart';

class _FakeAuth extends AuthController {
  _FakeAuth(super.ref) {
    state = const AuthState(signedIn: true);
  }
}

final _content = ScrollController();
final _drawer = ScrollController();

/// A view like the real ones: a narrow navigation list beside a long content
/// list. The keyboard focus stays on the root of the app, above both.
Widget _page(bool withField) => Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 100,
            child: ListView(
              controller: _drawer,
              children: [for (var i = 0; i < 40; i++) Text('nav $i')],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (withField) const TextField(key: Key('field')),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _content,
                    child: Column(
                      children: [
                        for (var i = 0; i < 100; i++)
                          SizedBox(height: 50, child: Text('row $i')),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

Future<void> _pump(WidgetTester tester, {bool withField = false}) async {
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => _page(withField)),
  ]);
  final container = ProviderContainer(overrides: [
    authControllerProvider.overrideWith(_FakeAuth.new),
  ]);
  addTearDown(container.dispose);
  tester.view.physicalSize = const Size(800, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppShortcuts(router: router, child: child!),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Page Down and Page Up scroll the content by about one page',
      (tester) async {
    await _pump(tester);
    expect(_content.offset, 0);

    await _press(tester, LogicalKeyboardKey.pageDown);
    final page = _content.position.viewportDimension;
    expect(_content.offset, closeTo(page * 0.9, 1));
    expect(_drawer.offset, 0, reason: 'the navigation list stays');

    await _press(tester, LogicalKeyboardKey.pageDown);
    expect(_content.offset, closeTo(page * 1.8, 1));

    await _press(tester, LogicalKeyboardKey.pageUp);
    expect(_content.offset, closeTo(page * 0.9, 1));
    await _press(tester, LogicalKeyboardKey.pageUp);
    expect(_content.offset, 0);
  });

  testWidgets('Page Down stops at the end of the content', (tester) async {
    await _pump(tester);
    for (var i = 0; i < 20; i++) {
      await _press(tester, LogicalKeyboardKey.pageDown);
    }
    expect(_content.offset, _content.position.maxScrollExtent);
  });

  testWidgets('the keys belong to a text field while the user types',
      (tester) async {
    await _pump(tester, withField: true);
    await tester.tap(find.byKey(const Key('field')));
    await tester.pump();
    await _press(tester, LogicalKeyboardKey.pageDown);
    expect(_content.offset, 0);
  });
}
