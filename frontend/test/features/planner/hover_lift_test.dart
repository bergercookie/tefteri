import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/planner/hover_lift.dart';

import 'planner_helpers.dart';

double _scale(WidgetTester tester) =>
    tester.widget<AnimatedScale>(find.byKey(const Key('task-hover-t1'))).scale;

double _handle(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(find.byKey(const Key('drag-handle-t1')))
    .opacity;

Future<TestGesture> _mouse(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: const Offset(900, 900));
  addTearDown(mouse.removePointer);
  return mouse;
}

void main() {
  testWidgets('a task row lifts and shows a grip while the mouse is over it',
      (tester) async {
    await pumpPlanner(tester, plannerApi());
    expect((_scale(tester), _handle(tester)), (1.0, 0.0));

    final mouse = await _mouse(tester);
    await mouse.moveTo(tester.getCenter(find.byKey(const Key('task-t1'))));
    await tester.pump();
    await tester.pump(hoverDuration * 2);
    expect(_scale(tester), hoverScale);
    expect(_handle(tester), 1.0);
    // the cursor becomes an open hand
    final region = tester.widget<MouseRegion>(find
        .descendant(
            of: find.byKey(const Key('drag-task-t1')),
            matching: find.byType(MouseRegion))
        .first);
    expect(region.cursor, SystemMouseCursors.grab);

    await mouse.moveTo(const Offset(900, 900));
    await tester.pump();
    await tester.pump(hoverDuration * 2);
    expect((_scale(tester), _handle(tester)), (1.0, 0.0));
    final calm = tester.widget<MouseRegion>(find
        .descendant(
            of: find.byKey(const Key('drag-task-t1')),
            matching: find.byType(MouseRegion))
        .first);
    expect(calm.cursor, MouseCursor.defer);
  });

  testWidgets('only the row under the pointer reacts', (tester) async {
    await pumpPlanner(tester, plannerApi());
    final mouse = await _mouse(tester);
    await mouse.moveTo(tester.getCenter(find.byKey(const Key('task-t2'))));
    await tester.pump(hoverDuration * 2);
    expect(_scale(tester), 1.0); // t1 stays calm
    expect(
        tester
            .widget<AnimatedScale>(find.byKey(const Key('task-hover-t2')))
            .scale,
        hoverScale);
  });

  testWidgets('the effect is instant when the system turns animations off',
      (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = _NoAnimations();
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpPlanner(tester, plannerApi());
    expect(
        tester
            .widget<AnimatedScale>(find.byKey(const Key('task-hover-t1')))
            .duration,
        Duration.zero);
  });

  testWidgets('the pane tells mouse users to drag a task onto the calendar',
      (tester) async {
    await pumpPlanner(tester, plannerApi());
    // the test platform is Android: touch users get the long-press text
    expect(find.text('Press and hold a task, then drag it onto the calendar.'),
        findsOneWidget);
  });

  testWidgets('desktop platforms get the short drag hint', (tester) async {
    await pumpPlanner(tester, plannerApi());
    expect(find.byKey(const Key('drag-hint')), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}

/// Accessibility settings with only "disable animations" set.
class _NoAnimations implements AccessibilityFeatures {
  @override
  bool get disableAnimations => true;

  // every other switch is off
  @override
  dynamic noSuchMethod(Invocation invocation) => false;
}
