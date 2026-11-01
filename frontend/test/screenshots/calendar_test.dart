@Tags(['screenshots'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/calendar/calendar_screen.dart';

import 'fixtures.dart';
import 'screenshot_helper.dart';

Map<String, Object?> _item(String type, String id, String title, DateTime start,
        {String? context = 'work'}) =>
    {
      'type': type,
      'id': id,
      'title': title,
      'start': start.toUtc().toIso8601String(),
      'end': start.add(const Duration(hours: 1)).toUtc().toIso8601String(),
      'all_day': false,
      'context': context,
      'effective_context': context ?? 'life',
      'connection_id': type == 'task' ? 'c1' : 'c2',
    };

FakeApi _api([Map<String, Object?> extra = const {}]) => FakeApi({
      'GET /calendar': [
        _item('entry', 'e1', 'Team standup', DateTime(2026, 11, 2, 9)),
        _item(
            'task', 't1', 'Write the release notes', DateTime(2026, 11, 2, 10)),
        _item('entry', 'e3', 'Design review', DateTime(2026, 11, 3, 14)),
        _item('entry', 'e2', 'Dentist', DateTime(2026, 11, 4, 16),
            context: 'life'),
      ],
      'GET /tasks': [
        taskJson('t2', 'Buy a birthday present', context: null),
        taskJson('t4', 'Update the road map'),
      ],
      ...extra,
    });

void main() {
  testWidgets('calendar with a scheduled task', (tester) async {
    await pumpScreen(tester, _api(), CalendarScreen(initialDate: day));
    await saveScreenshot('calendar-week');
  });

  testWidgets('unsupported app message', (tester) async {
    await pumpScreen(
        tester,
        _api({
          'PUT /tasks/t2/schedule': const ApiFailure(
              409,
              'Home tasks does not support this action (task_time).',
              'not_supported'),
        }),
        CalendarScreen(initialDate: day));
    await tester.tap(find.byKey(const Key('unscheduled-t2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('schedule-confirm')));
    await tester.pumpAndSettle();
    await saveScreenshot('calendar-unsupported');
  });
}
