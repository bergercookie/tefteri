import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tefteri/core/auth_controller.dart';
import 'package:tefteri/core/pane_widths.dart';
import 'package:tefteri/core/shell.dart';
import 'package:tefteri/features/planner/planner_screen.dart';
import 'package:tefteri/features/planner/task_pane.dart';

import '../features/planner/planner_helpers.dart';

class _SignedIn extends AuthController {
  _SignedIn(super.ref) {
    state = const AuthState(signedIn: true);
  }
}

Future<ProviderContainer> _pumpShell(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(overrides: [
    authControllerProvider.overrideWith(_SignedIn.new),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: AppShell(title: 'T', body: SizedBox())),
  ));
  await tester.pumpAndSettle();
  return container;
}

/// The width of the sidebar: where its divider starts.
double _sidebar(WidgetTester tester) =>
    tester.getTopLeft(find.byKey(const Key('sidebar-resize'))).dx;

Future<void> _drag(WidgetTester tester, String key, double dx) async {
  await tester.drag(find.byKey(Key(key)), Offset(dx, 0));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('PaneWidth', () {
    test('stays inside its limits and goes back to the standard width', () {
      final w = PaneWidth('w', 300, min: 200, max: 400);
      w.set(50);
      expect(w.state, 200);
      w.set(900);
      expect(w.state, 400);
      w.set(320);
      expect(w.state, 320);
      w.reset();
      expect(w.state, 300);
    });

    test('keeps the width for the next start', () async {
      final first = PaneWidth('kept', 300, min: 200, max: 400)..set(350);
      await first.save();
      final second = PaneWidth('kept', 300, min: 200, max: 400);
      await Future<void>.delayed(Duration.zero);
      expect(second.state, 350);
      // A value outside the limits (saved by an older version) is cut.
      SharedPreferences.setMockInitialValues({'kept': 9000.0});
      final third = PaneWidth('kept', 300, min: 200, max: 400);
      await Future<void>.delayed(Duration.zero);
      expect(third.state, 400);
    });
  });

  group('the sidebar', () {
    testWidgets('is resized by dragging its divider', (tester) async {
      final container = await _pumpShell(tester, railExtendedMinWidth);
      expect(find.byKey(const Key('sidebar-resize')), findsOneWidget);
      final before = _sidebar(tester);
      await _drag(tester, 'sidebar-resize', 50);
      expect(_sidebar(tester), closeTo(before + 50, 1));
      await _drag(tester, 'sidebar-resize', -500);
      expect(_sidebar(tester), 200); // the narrowest
      await _drag(tester, 'sidebar-resize', 800);
      // Never more than two fifths of the window, and never more than 360.
      expect(_sidebar(tester), lessThanOrEqualTo(360));
      expect(container.read(sidebarWidthProvider), lessThanOrEqualTo(360));
    });

    testWidgets('goes back to the standard width on a double click',
        (tester) async {
      await _pumpShell(tester, railExtendedMinWidth);
      final standard = _sidebar(tester);
      await _drag(tester, 'sidebar-resize', 60);
      expect(_sidebar(tester), isNot(closeTo(standard, 1)));
      final at = tester.getCenter(find.byKey(const Key('sidebar-resize')));
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(at);
      await tester.pumpAndSettle();
      expect(_sidebar(tester), closeTo(standard, 1));
    });

    testWidgets('is resized with the arrow keys', (tester) async {
      await _pumpShell(tester, railExtendedMinWidth);
      final before = _sidebar(tester);
      // A click on the divider gives it the focus; then the arrow keys work.
      await tester
          .tapAt(tester.getCenter(find.byKey(const Key('sidebar-resize'))));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(_sidebar(tester), closeTo(before + 16, 1));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(_sidebar(tester), closeTo(before, 1));
    });

    testWidgets('the compact rail has no divider to drag', (tester) async {
      await _pumpShell(tester, railMinWidth);
      expect(find.byKey(const Key('sidebar-resize')), findsNothing);
    });

    testWidgets('keeps the dragged width in the saved settings',
        (tester) async {
      await _pumpShell(tester, railExtendedMinWidth);
      await _drag(tester, 'sidebar-resize', 40);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('sidebar_width'), greaterThan(232));
    });
  });

  group('the task list of the planner', () {
    double taskPane(WidgetTester tester) =>
        tester.getSize(find.byType(TaskPane)).width;

    testWidgets('is resized by dragging its divider', (tester) async {
      await pumpPlanner(tester, plannerApi());
      expect(taskPane(tester), 360);
      await _drag(tester, 'task-pane-resize', 40);
      expect(taskPane(tester), closeTo(400, 1));
      await _drag(tester, 'task-pane-resize', -400);
      expect(taskPane(tester), 260); // the narrowest
    });

    testWidgets('leaves the calendar its minimum width', (tester) async {
      await pumpPlanner(tester, plannerApi());
      await _drag(tester, 'task-pane-resize', 900);
      final calendar = tester.getSize(find.byKey(const Key('calendar-pane')));
      expect(calendar.width, greaterThanOrEqualTo(calendarMinWidth - 1));
    });

    testWidgets('goes back to 360 on a double click', (tester) async {
      await pumpPlanner(tester, plannerApi());
      await _drag(tester, 'task-pane-resize', 60);
      final at = tester.getCenter(find.byKey(const Key('task-pane-resize')));
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(at);
      await tester.pumpAndSettle();
      expect(taskPane(tester), 360);
    });
  });
}
