import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/core/calendar_color.dart';
import 'package:tefteri/core/planning_models.dart';
import 'package:tefteri/theme/theme.dart';

import 'planner_helpers.dart';

void main() {
  group('parseCalendarColor', () {
    test('reads #rrggbb in either case', () {
      expect(
          parseCalendarColor('#d50000'), const Color.fromARGB(255, 213, 0, 0));
      expect(parseCalendarColor('#33B679'),
          const Color.fromARGB(255, 51, 182, 121));
    });

    test('answers null for anything else, so the app keeps its own color', () {
      for (final bad in [
        null,
        '',
        'red',
        '#fff',
        '#12345',
        'd50000',
        '#gg0000'
      ]) {
        expect(parseCalendarColor(bad), isNull, reason: '$bad');
      }
    });
  });

  test('the models keep the color of the calendar', () {
    final item = CalendarItem.fromJson(const {
      'type': 'entry',
      'id': 'e1',
      'title': 'x',
      'all_day': false,
      'color': '#039be5',
    });
    expect(item.color, '#039be5');
    expect(
        CalendarItem.fromJson(const {'type': 'task', 'id': 't', 'title': 'y'})
            .color,
        isNull);
    final entry = PlanEntry.fromJson(const {
      'id': 'e',
      'connection_id': 'c',
      'title': 'z',
      'all_day': false,
      'color': '#d50000',
    });
    expect(entry.color, '#d50000');
  });

  testWidgets('an event shows the color that the user chose for its calendar',
      (tester) async {
    final api = plannerApi(calendar: [
      calItem('entry', 'red', 'Work meeting',
          start: DateTime(2026, 11, 4, 9), color: '#d50000'),
      calItem('entry', 'green', 'Home',
          start: DateTime(2026, 11, 4, 11), color: '#33b679'),
      calItem('entry', 'none', 'No color', start: DateTime(2026, 11, 4, 13)),
      calItem('entry', 'day', 'All day thing',
          start: DateTime(2026, 11, 5),
          end: DateTime(2026, 11, 6),
          allDay: true,
          color: '#039be5'),
    ]);
    await pumpPlanner(tester, api);
    Color tint(String key) =>
        (tester.widget<Container>(find.byKey(Key(key))).decoration!
                as BoxDecoration)
            .color!;
    Color accent(String key) =>
        tester.widget<Container>(find.byKey(Key(key))).color!;

    // The strong edge is exactly the color of the calendar.
    expect(
        accent('block-accent-entry-red'), const Color.fromARGB(255, 213, 0, 0));
    expect(accent('block-accent-entry-green'),
        const Color.fromARGB(255, 51, 182, 121));
    // The body is that color, softened, so that the text reads on it.
    expect(tint('block-entry-red'), isNot(accent('block-accent-entry-red')));
    expect(tint('block-entry-red'), isNot(tint('block-entry-green')));
    final red = tint('block-entry-red');
    expect(red.r, greaterThan(red.g)); // still reads as red
    // A calendar with no color keeps the look of the app.
    const colors = TefteriColors.light;
    expect(tint('block-entry-none'), colors.eventContainer);
    expect(accent('block-accent-entry-none'), colors.event);
    // The all-day chip takes the color as well.
    final chip = (tester
            .widget<Container>(find.byKey(const Key('allday-entry-day')))
            .decoration! as BoxDecoration)
        .border! as Border;
    expect(chip.left.color, const Color.fromARGB(255, 3, 155, 229));
  });

  testWidgets('a task shows the color of its project', (tester) async {
    final api = plannerApi(calendar: [
      calItem('task', 'blue', 'Fix the form',
          start: DateTime(2026, 11, 4, 9), color: '#039be5', status: 'open'),
      calItem('task', 'plain', 'No project color',
          start: DateTime(2026, 11, 4, 11), status: 'open'),
      calItem('task', 'done', 'Finished',
          start: DateTime(2026, 11, 4, 13), color: '#039be5', status: 'done'),
    ]);
    await pumpPlanner(tester, api);
    Color tint(String key) =>
        (tester.widget<Container>(find.byKey(Key(key))).decoration!
                as BoxDecoration)
            .color!;
    Color accent(String key) =>
        tester.widget<Container>(find.byKey(Key(key))).color!;
    const colors = TefteriColors.light;
    expect(accent('block-accent-task-blue'),
        const Color.fromARGB(255, 3, 155, 229));
    expect(tint('block-task-blue'), isNot(colors.taskContainer));
    // Without a project color, the colors of the app stay.
    expect(accent('block-accent-task-plain'), colors.task);
    expect(tint('block-task-plain'), colors.taskContainer);
    // A finished task stays sage, whatever its project.
    expect(accent('block-accent-task-done'), colors.done);
  });

  testWidgets('the task list shows the project color on a planned task',
      (tester) async {
    final api = plannerApi(
        tasksFor: (_) => [
              {
                ...dueTask('t1', 'Fix the form',
                    due: DateTime(2026, 11, 4, 10)),
                'project_color': '#039be5',
              },
              dueTask('t2', 'Reply to Sam', due: DateTime(2026, 11, 4, 12)),
            ]);
    await pumpPlanner(tester, api);
    Color icon(String id) =>
        tester.widget<Icon>(find.byKey(Key('scheduled-$id'))).color!;
    expect(icon('t1'), const Color.fromARGB(255, 3, 155, 229));
    expect(icon('t2'), TefteriColors.light.task);
  });
}
