import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tefteri/features/planner/planner_screen.dart';

import '../../support/fake_api.dart';
import 'planner_helpers.dart';

Finder _column(String day) => find.byKey(Key('day-column-$day'));

int _columns(WidgetTester tester) => tester
    .widgetList(find.byWidgetPredicate((w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('day-column-')))
    .length;

String _label(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('week-label'))).data!;

Future<void> _choose(WidgetTester tester, String span) async {
  await tester.tap(find.byKey(const Key('planner-span-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('planner-span-$span')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows the week by default', (tester) async {
    await pumpPlanner(tester, plannerApi());
    expect(_columns(tester), 7);
    expect(_label(tester), 'Week of 2026-11-02');
    expect(
        find.descendant(
            of: find.byKey(const Key('planner-span-button')),
            matching: find.text('Week')),
        findsOneWidget);
  });

  testWidgets(
      'three days: the arrows move by three days and the choice is '
      'kept', (tester) async {
    await pumpPlanner(tester, plannerApi());
    await _choose(tester, 'threeDays');

    expect(_columns(tester), 3);
    expect(_column('2026-11-02'), findsOneWidget);
    expect(_column('2026-11-04'), findsOneWidget);
    expect(_column('2026-11-05'), findsNothing);
    expect(_label(tester), '2026-11-02 to 2026-11-04');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('planner_span'), 'threeDays');

    await tester.tap(find.byKey(const Key('next-week')));
    await tester.pumpAndSettle();
    expect(_label(tester), '2026-11-05 to 2026-11-07');
    final next = tester.widget<IconButton>(find.byKey(const Key('next-week')));
    expect(next.tooltip, 'Next 3 days (Right arrow)');
  });

  testWidgets('a saved day view opens on the first day', (tester) async {
    SharedPreferences.setMockInitialValues({'planner_span': 'day'});
    final api = plannerApi();
    await pumpPlanner(tester, api);
    await tester.pumpAndSettle();

    expect(_columns(tester), 1);
    expect(_label(tester), 'Wed 2026-11-04');
    await tester.tap(find.byKey(const Key('prev-week')));
    await tester.pumpAndSettle();
    expect(_label(tester), 'Tue 2026-11-03');
    expect(api.where('GET /calendar').last.query['from'],
        DateTime(2026, 11, 3).toUtc().toIso8601String());

    // Back to the week: it is the week of that day.
    await _choose(tester, 'week');
    expect(_columns(tester), 7);
    expect(_label(tester), 'Week of 2026-11-02');
  });

  testWidgets('from the current week, the day view shows today',
      (tester) async {
    await pumpWithApi(
        tester,
        plannerApi(),
        PlannerScreen(
            initialDate: wednesday, clock: () => DateTime(2026, 11, 6, 9)),
        size: const Size(1000, 2400));
    await _choose(tester, 'day');
    expect(_label(tester), 'Fri 2026-11-06');
  });

  testWidgets('the menu fits a phone screen', (tester) async {
    await pumpPlanner(tester, plannerApi(), size: const Size(360, 640));
    await tester.tap(find.byKey(const Key('tab-calendar')));
    await tester.pumpAndSettle();
    await _choose(tester, 'threeDays');
    expect(_columns(tester), 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a phone opens on one day, without a saved choice',
      (tester) async {
    await pumpPlanner(tester, plannerApi(), size: const Size(360, 640));
    await tester.tap(find.byKey(const Key('tab-calendar')));
    await tester.pumpAndSettle();
    expect(_columns(tester), 1);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('planner_span'), isNull);
  });

  testWidgets('a tablet width opens on three days', (tester) async {
    await pumpPlanner(tester, plannerApi(), size: const Size(500, 900));
    await tester.tap(find.byKey(const Key('tab-calendar')));
    await tester.pumpAndSettle();
    expect(_columns(tester), 3);
  });

  testWidgets('a saved choice wins over the width, and Automatic undoes it',
      (tester) async {
    SharedPreferences.setMockInitialValues({'planner_span': 'week'});
    await pumpPlanner(tester, plannerApi(), size: const Size(360, 640));
    await tester.tap(find.byKey(const Key('tab-calendar')));
    await tester.pumpAndSettle();
    expect(_columns(tester), 7);

    await _choose(tester, 'auto');
    expect(_columns(tester), 1);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('planner_span'), isNull);
  });
}
