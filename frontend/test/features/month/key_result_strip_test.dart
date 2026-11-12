import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/month/key_result_strip.dart';
import 'package:tefteri/features/month/month_models.dart';

import '../../support/fake_api.dart';

MonthEntry _entry({int linked = 1}) => MonthEntry.fromJson(
      monthlyEntryJson('e1', 'p1', 'Theme', linkedKeyResults: linked),
    );

void main() {
  testWidgets('shows key result progress, target and deadline', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: KeyResultStrip(
          entry: _entry(),
          keyResults: [
            monthlyKeyResultJson(
              id: 'kr1',
              goalTitle: 'Grow the project',
              metric: 'Active users',
              startValue: 10,
              currentValue: 15,
              target: 30,
              deadline: '2030-12-31',
              currentAt: '2030-03-20T09:00:00Z',
              themeIds: const ['p1'],
            ),
          ],
        ),
      ),
    ));
    expect(find.textContaining('Grow the project'), findsOneWidget);
    expect(find.textContaining('Start 10'), findsOneWidget);
    expect(find.textContaining('Latest 15'), findsOneWidget);
    expect(find.textContaining('Target 30'), findsOneWidget);
    expect(find.textContaining('2030-12-31'), findsOneWidget);
  });

  testWidgets(
      'shows the no-theme and unusable-theme flags without a link control',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: KeyResultStrip(
          entry: _entry(),
          keyResults: [
            monthlyKeyResultJson(
              id: 'kr1',
              themeIds: const [],
              flags: const [
                {
                  'code': 'no_theme_in_focus',
                  'actions': ['open_picker']
                },
                {
                  'code': 'no_usable_theme',
                  'actions': ['open_annual_plan']
                },
              ],
            ),
          ],
        ),
      ),
    ));
    expect(find.textContaining('No usable theme'), findsOneWidget);
    expect(find.byKey(const Key('annual-plan-kr1')), findsOneWidget);
    expect(find.textContaining('No theme in focus'), findsOneWidget);
    expect(find.byKey(const Key('link-theme-kr1')), findsNothing);
  });

  testWidgets('allows a theme with no linked key result', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: KeyResultStrip(entry: _entry(linked: 0), keyResults: const []),
      ),
    ));
    expect(find.text('Not linked to a key result'), findsOneWidget);
  });
}
