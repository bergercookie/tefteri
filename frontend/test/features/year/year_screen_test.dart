import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/year/year_screen.dart';

import '../../support/fake_api.dart';

const _path = 'GET /views/year/2026';

Map<String, Object?> _year() => periodJson(
      'year',
      '2026-01-01',
      '2027-01-01',
      goals: [
        goalJson('g1', 'Run a marathon', progress: 0.75),
        goalJson('g2', 'Read more', status: 'done', progress: 1),
      ],
      tasks: [taskJson('t1', 'Book race')],
    );

Future<void> _pump(WidgetTester tester, FakeApi api) =>
    pumpWithApi(tester, api, const YearScreen(initialYear: 2026));

void main() {
  testWidgets('shows year goals and progress; no events section',
      (tester) async {
    final api = FakeApi({_path: _year()});
    await _pump(tester, api);
    expect(find.text('2026'), findsOneWidget);
    expect(find.text('Run a marathon'), findsOneWidget);
    expect(find.text('75%'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('Book race'), findsOneWidget);
    expect(find.text('Events'), findsNothing);
    expect(api.where(_path).first.query['context'], 'all');
  });

  testWidgets('next year loads the next year view', (tester) async {
    final api = FakeApi({
      _path: _year(),
      'GET /views/year/2027': periodJson('year', '2027-01-01', '2028-01-01'),
    });
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('next-period')));
    await tester.pumpAndSettle();
    expect(api.where('GET /views/year/2027'), hasLength(1));
    expect(find.text('2027'), findsOneWidget);
  });

  testWidgets('a task can be scheduled from the year view', (tester) async {
    final api = FakeApi({
      _path: _year(),
      'PUT /tasks/t1/schedule': taskJson('t1', 'x'),
    });
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('task-menu-t1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Schedule'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('schedule-confirm')));
    await tester.pumpAndSettle();
    final put = api.where('PUT /tasks/t1/schedule').single;
    final data = put.data! as Map;
    expect(data['start'], isNotNull);
    expect(data['end'], isNotNull);
    expect(DateTime.parse('${data['start']}').toLocal().year, 2026);
  });
}
