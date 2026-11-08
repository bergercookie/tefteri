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
    // Single tasks are not listed in the year view.
    expect(find.text('Book race'), findsNothing);
    expect(find.text('Tasks'), findsNothing);
    expect(find.text('Events'), findsNothing);
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
}
