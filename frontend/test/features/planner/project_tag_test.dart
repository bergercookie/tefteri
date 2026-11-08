import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/theme/theme.dart';

import 'planner_helpers.dart';

String _tag(WidgetTester tester, String id) => tester
    .widget<Text>(find.descendant(
        of: find.byKey(Key('project-tag-$id')), matching: find.byType(Text)))
    .data!;

void main() {
  testWidgets('a task block names its project under the title', (tester) async {
    final api = plannerApi(calendar: [
      calItem('task', 't1', 'Fix the contact form',
          start: DateTime(2026, 11, 4, 14),
          end: DateTime(2026, 11, 4, 15),
          project: 'Website'),
    ]);
    await pumpPlanner(tester, api);
    expect(find.byKey(const Key('project-tag-t1')), findsOneWidget);
    expect(_tag(tester, 't1'), 'Website');
    // The tag is on its own line, under the title.
    final title = tester.getRect(find.text('Fix the contact form'));
    final tag = tester.getRect(find.byKey(const Key('project-tag-t1')));
    expect(tag.top, greaterThanOrEqualTo(title.bottom - 1));
    // The time still shows in a one-hour block.
    expect(find.textContaining('14:00'), findsWidgets);
  });

  testWidgets('the tag is a solid box with square corners', (tester) async {
    final api = plannerApi(calendar: [
      calItem('task', 't1', 'Fix the form',
          start: DateTime(2026, 11, 4, 14), project: 'Website'),
    ]);
    await pumpPlanner(tester, api);
    final box = tester.widget<Container>(find.descendant(
        of: find.byKey(const Key('project-tag-t1')),
        matching: find.byType(Container)));
    final scheme =
        Theme.of(tester.element(find.byKey(const Key('project-tag-t1'))))
            .colorScheme;
    expect(box.color, scheme.onSurfaceVariant); // solid, not transparent
    expect(box.decoration, isNull); // no rounded corners
  });

  testWidgets('a short block shows the tag after the title', (tester) async {
    final api = plannerApi(calendar: [
      calItem('task', 't1', 'Quick call',
          start: DateTime(2026, 11, 4, 14),
          end: DateTime(2026, 11, 4, 14, 30),
          project: 'Inbox'),
    ]);
    await pumpPlanner(tester, api);
    final title = tester.getRect(find.text('Quick call'));
    final tag = tester.getRect(find.byKey(const Key('project-tag-t1')));
    expect(tag.left, greaterThan(title.left));
    expect((tag.center.dy - title.center.dy).abs(), lessThan(8)); // same line
    expect(tester.takeException(), isNull); // nothing overflows
  });

  testWidgets('a long project name is cut, and the full name is a tooltip',
      (tester) async {
    final api = plannerApi(calendar: [
      calItem('task', 't1', 'Review',
          start: DateTime(2026, 11, 4, 14),
          project: 'A project with a very long name that keeps going on'),
    ]);
    await pumpPlanner(tester, api);
    final tag = tester.getRect(find.byKey(const Key('project-tag-t1')));
    final column =
        tester.getRect(find.byKey(const Key('day-column-2026-11-04')));
    expect(tag.right, lessThanOrEqualTo(column.right));
    expect(tester.takeException(), isNull);
    final tip = tester.widget<Tooltip>(find.descendant(
        of: find.byKey(const Key('project-tag-t1')),
        matching: find.byType(Tooltip)));
    expect(tip.message,
        'Project: A project with a very long name that keeps going on');
  });

  testWidgets('an all-day task shows its project in its chip', (tester) async {
    final api = plannerApi(calendar: [
      calItem('task', 'c5', 'Pay the invoice',
          start: DateTime(2026, 11, 5),
          end: DateTime(2026, 11, 6),
          allDay: true,
          project: 'Taxes'),
    ]);
    await pumpPlanner(tester, api);
    expect(_tag(tester, 'c5'), 'Taxes');
    expect(tester.takeException(), isNull);
  });

  testWidgets('events and tasks without a project have no tag', (tester) async {
    final api = plannerApi(calendar: [
      calItem('entry', 'e1', 'Team standup',
          start: DateTime(2026, 11, 3, 9), end: DateTime(2026, 11, 3, 9, 30)),
      calItem('task', 't2', 'Loose task', start: DateTime(2026, 11, 4, 10)),
    ]);
    await pumpPlanner(tester, api);
    expect(find.byKey(const Key('project-tag-e1')), findsNothing);
    expect(find.byKey(const Key('project-tag-t2')), findsNothing);
  });

  testWidgets('the tag is readable in the dark theme too', (tester) async {
    final api = plannerApi(calendar: [
      calItem('task', 't1', 'Fix the form',
          start: DateTime(2026, 11, 4, 14), project: 'Website'),
    ]);
    await pumpPlanner(tester, api);
    double contrast(Color a, Color b) {
      final la = a.computeLuminance() + 0.05;
      final lb = b.computeLuminance() + 0.05;
      return la > lb ? la / lb : lb / la;
    }

    for (final b in Brightness.values) {
      final s = tefteriScheme(b);
      expect(contrast(s.onSurfaceVariant, s.surface), greaterThan(4.5),
          reason: b.name);
    }
  });

  testWidgets('tags fit the narrow columns of a phone', (tester) async {
    final api = plannerApi(calendar: [
      calItem('task', 't1', 'Fix the contact form',
          start: DateTime(2026, 11, 4, 14), project: 'Website redesign'),
      calItem('task', 'c5', 'Pay the invoice',
          start: DateTime(2026, 11, 4),
          end: DateTime(2026, 11, 5),
          allDay: true,
          project: 'Taxes and accounting'),
    ]);
    await pumpPlanner(tester, api);
    tester.view.physicalSize = const Size(390, 800);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('project-tag-t1')), findsOneWidget);
    expect(find.byKey(const Key('project-tag-c5')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
