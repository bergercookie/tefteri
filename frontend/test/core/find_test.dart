import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/core/auth_controller.dart';
import 'package:tefteri/core/find.dart';
import 'package:tefteri/core/shortcuts/app_shortcuts.dart';
import 'package:tefteri/core/shortcuts/keymap.dart';
import 'package:go_router/go_router.dart';

class _SignedIn extends AuthController {
  _SignedIn(super.ref) {
    state = const AuthState(signedIn: true);
  }
}

Future<ProviderContainer> _pump(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(800, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(body: FindHost(child: page)),
    ),
  ));
  await tester.pumpAndSettle();
  return container;
}

Future<void> _search(
    WidgetTester tester, ProviderContainer c, String query) async {
  c.read(findProvider.notifier).open();
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('find-field')), query);
  await tester.pumpAndSettle();
}

const _page = Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text('Buy soil'),
    SizedBox(height: 40),
    Text('Prune the roses'),
    SizedBox(height: 40),
    Text('BUY a spade, buy a rake'),
  ],
);

void main() {
  testWidgets('finds every place of a word, in reading order', (tester) async {
    final c = await _pump(tester, _page);
    await _search(tester, c, 'buy');
    final state = c.read(findProvider);
    expect(state.matches, hasLength(3)); // upper and lower case alike
    expect(find.byKey(const Key('find-count')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('find-count'))).data,
        '1 of 3');
    // The first match is the first line of the page.
    final first = state.matches.first.screenRects().single;
    final line = tester.getRect(find.text('Buy soil'));
    expect(first.top, greaterThanOrEqualTo(line.top - 3));
    expect(first.bottom, lessThanOrEqualTo(line.bottom + 3));
    expect(first.left, closeTo(line.left, 3));
    expect(first.width, lessThan(line.width)); // only the word, not the line
  });

  testWidgets('the marks are drawn only while the bar is open', (tester) async {
    final c = await _pump(tester, _page);
    expect(find.byKey(const Key('find-marks')), findsNothing);
    await _search(tester, c, 'roses');
    expect(find.byKey(const Key('find-marks')), findsOneWidget);
    expect(find.byKey(const Key('find-bar')), findsOneWidget);
    await tester.tap(find.byKey(const Key('find-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('find-marks')), findsNothing);
    expect(c.read(findProvider).open, isFalse);
  });

  testWidgets('next and previous go round the matches', (tester) async {
    final c = await _pump(tester, _page);
    await _search(tester, c, 'buy');
    String count() =>
        tester.widget<Text>(find.byKey(const Key('find-count'))).data!;
    expect(count(), '1 of 3');
    await tester.tap(find.byKey(const Key('find-next')));
    await tester.pumpAndSettle();
    expect(count(), '2 of 3');
    await tester.tap(find.byKey(const Key('find-next')));
    await tester.tap(find.byKey(const Key('find-next')));
    await tester.pumpAndSettle();
    expect(count(), '1 of 3'); // round the end
    await tester.tap(find.byKey(const Key('find-previous')));
    await tester.pumpAndSettle();
    expect(count(), '3 of 3'); // and back round the start
    // Enter goes to the next match, Shift+Enter to the one before.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(count(), '1 of 3');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(count(), '3 of 3');
  });

  testWidgets('says when nothing matches', (tester) async {
    final c = await _pump(tester, _page);
    await _search(tester, c, 'zebra');
    expect(tester.widget<Text>(find.byKey(const Key('find-count'))).data,
        'No matches');
    expect(c.read(findProvider).matches, isEmpty);
    expect(
        tester.widget<IconButton>(find.byKey(const Key('find-next'))).onPressed,
        isNull);
  });

  testWidgets('Escape closes the bar', (tester) async {
    final c = await _pump(tester, _page);
    await _search(tester, c, 'soil');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('find-bar')), findsNothing);
    expect(c.read(findProvider).open, isFalse);
  });

  testWidgets('text that is hidden is not found', (tester) async {
    final c = await _pump(
      tester,
      const Column(
        children: [
          Text('visible apple'),
          Offstage(child: Text('offstage apple')),
          SizedBox(
            height: 100,
            child: IndexedStack(
              index: 0,
              children: [Text('shown apple'), Text('hidden apple')],
            ),
          ),
        ],
      ),
    );
    await _search(tester, c, 'apple');
    final texts = [
      for (final m in c.read(findProvider).matches)
        m.paragraph.text.toPlainText(),
    ];
    expect(texts, ['visible apple', 'shown apple']);
  });

  testWidgets('a match that is scrolled out of the area has no marks',
      (tester) async {
    final c = await _pump(
      tester,
      SizedBox(
        height: 200,
        child: ListView(
          children: [
            for (var i = 0; i < 40; i++)
              SizedBox(height: 50, child: Text('row $i needle')),
          ],
        ),
      ),
    );
    await _search(tester, c, 'needle');
    final matches = c.read(findProvider).matches;
    expect(matches, isNotEmpty);
    // The first rows are in the 200 pixels that show; the rest are not.
    expect(matches.first.screenRects(), isNotEmpty);
    expect(matches.where((m) => m.screenRects().isNotEmpty).length,
        lessThan(matches.length));
  });

  testWidgets('going to a match scrolls it into view', (tester) async {
    final c = await _pump(
      tester,
      SizedBox(
        height: 200,
        child: ListView(
          children: [
            for (var i = 0; i < 40; i++)
              SizedBox(height: 50, child: Text('row $i')),
            const SizedBox(height: 50, child: Text('the needle')),
            for (var i = 0; i < 40; i++)
              SizedBox(height: 50, child: Text('tail $i')),
          ],
        ),
      ),
    );
    // The needle is far below what shows, so the list has not built it yet.
    await _search(tester, c, 'needle');
    expect(c.read(findProvider).matches, isEmpty);
    // Search again after the list is scrolled near it: found, and shown.
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    c.read(findProvider.notifier).refresh(reveal: true);
    await tester.pumpAndSettle();
    final matches = c.read(findProvider).matches;
    expect(matches, hasLength(1));
    expect(matches.single.screenRects(), isNotEmpty);
  });

  testWidgets('Ctrl+F opens the bar, also while typing in a field',
      (tester) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: [
      authControllerProvider.overrideWith(_SignedIn.new),
    ]);
    addTearDown(container.dispose);
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(
          body: Column(children: [Text('Write the report'), TextField()]),
        ),
      ),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        builder: (_, child) => AppShortcuts(
          router: router,
          child: FindHost(child: child!),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('find-bar')), findsNothing);
    // The help list names the shortcut.
    expect(appShortcuts.map((s) => s.keys), contains('Ctrl+F'));

    // Focus the text field of the page, then press Ctrl+F.
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('find-bar')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('find-field')), 'report');
    await tester.pumpAndSettle();
    expect(container.read(findProvider).matches, hasLength(1));
    // The bar searches the page, not its own text.
    await tester.enterText(find.byKey(const Key('find-field')), 'Find on');
    await tester.pumpAndSettle();
    expect(container.read(findProvider).matches, isEmpty);
  });

  test('findInTree reads a render tree without a bar', () {
    // A bare check of the search itself: an empty query finds nothing.
    expect(
        findInTree(
            RenderParagraph(const TextSpan(text: 'x'),
                textDirection: TextDirection.ltr),
            ''),
        isEmpty);
  });
}
