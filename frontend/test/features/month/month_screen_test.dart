import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/month/month_screen.dart';

import '../../support/fake_api.dart';

const _path = 'GET /views/month/2026-11-01';

Map<String, Object?> _month() => periodJson(
      'month',
      '2026-11-01',
      '2026-12-01',
      goals: [
        goalJson('g1', 'Launch site',
            periodType: 'month', periodStart: '2026-11-01', progress: 0.25),
      ],
      tasks: [taskJson('t1', 'Draft copy')],
    );

Future<void> _pump(WidgetTester tester, FakeApi api) =>
    pumpWithApi(tester, api, MonthScreen(initialDate: DateTime(2026, 11, 15)));

void main() {
  testWidgets('shows month goals, progress and tasks', (tester) async {
    final api = FakeApi({_path: _month()});
    await _pump(tester, api);
    expect(find.text('Nov 2026'), findsOneWidget);
    expect(find.text('Launch site'), findsOneWidget);
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byKey(const Key('goal-progress-g1')))
            .value,
        0.25);
    expect(find.text('Draft copy'), findsOneWidget);
    expect(api.where(_path).first.query['context'], 'all');
  });

  testWidgets('next month loads the first day of December', (tester) async {
    final api = FakeApi({
      _path: _month(),
      'GET /views/month/2026-12-01':
          periodJson('month', '2026-12-01', '2027-01-01'),
    });
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('next-period')));
    await tester.pumpAndSettle();
    expect(api.where('GET /views/month/2026-12-01'), hasLength(1));
    expect(find.text('Dec 2026'), findsOneWidget);
  });

  testWidgets('schedule from the month view sends the task time',
      (tester) async {
    final api = FakeApi({
      _path: _month(),
      'PUT /tasks/t1/schedule': taskJson('t1', 'x'),
    });
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('task-menu-t1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Schedule'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('schedule-day')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2026-11-20').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('schedule-confirm')));
    await tester.pumpAndSettle();
    final put = api.where('PUT /tasks/t1/schedule').single;
    expect((put.data! as Map)['start'],
        DateTime(2026, 11, 20, 9).toUtc().toIso8601String());
  });
}
