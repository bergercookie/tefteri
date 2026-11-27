@Tags(['screenshots'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/daily/daily_providers.dart';
import 'package:tefteri/features/daily/daily_screen.dart';

import 'fixtures.dart';
import 'screenshot_helper.dart';

FakeApi _api() => FakeApi({
      'GET /views/day/2026-11-02': dayView(),
      'GET /connections': connections,
    });

/// The clock of the screenshot: [hour] o'clock on the day of the fake data.
Override _at(int hour) => dailyClockProvider
    .overrideWithValue(() => DateTime(day.year, day.month, day.day, hour));

void main() {
  testWidgets('daily view', (tester) async {
    await pumpScreen(tester, _api(), DailyScreen(initialDate: day),
        overrides: [_at(8)]);
    await saveScreenshot('daily-view');
  });

  testWidgets('daily view of a day that has passed', (tester) async {
    // Three days later: every event of the day is over, and grayed out.
    await pumpScreen(tester, _api(), DailyScreen(initialDate: day), overrides: [
      dailyClockProvider.overrideWithValue(
          () => DateTime(day.year, day.month, day.day + 3, 9)),
    ]);
    await saveScreenshot('daily-past-day');
  });

  testWidgets('daily view with an event that is over', (tester) async {
    // At 10:00 the standup of 09:00 is over, and the dentist is next.
    await pumpScreen(tester, _api(), DailyScreen(initialDate: day),
        overrides: [_at(10)]);
    await saveScreenshot('daily-past-events');
  });

  testWidgets('quick add', (tester) async {
    await pumpScreen(tester, _api(), DailyScreen(initialDate: day),
        overrides: [_at(8)]);
    await tester.enterText(
        find.byKey(const Key('quick-add-field')), 'Book the train tickets');
    await tester.pumpAndSettle();
    await saveScreenshot('daily-quick-add');
  });

  testWidgets('daily note sheet', (tester) async {
    await pumpScreen(tester, _api(), DailyScreen(initialDate: day),
        overrides: [_at(8)]);
    await tester.tap(find.byKey(const Key('add-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-note')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('daily-note-field')),
        'Agreed with Sam to move the review to Thursday.');
    await tester.pumpAndSettle();
    await saveScreenshot('daily-note-sheet');
  });

  testWidgets('daily note sheet on a phone', (tester) async {
    await pumpScreen(tester, _api(), DailyScreen(initialDate: day),
        overrides: [_at(8)], size: const Size(390, 760));
    await tester.tap(find.byKey(const Key('add-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-note')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('daily-note-field')),
        'Agreed with Sam to move the review to Thursday.');
    await tester.pumpAndSettle();
    await saveScreenshot('daily-note-sheet-phone');
  });

  testWidgets('the add menu', (tester) async {
    await pumpScreen(tester, _api(), DailyScreen(initialDate: day),
        overrides: [_at(8)]);
    await tester.tap(find.byKey(const Key('add-button')));
    await tester.pumpAndSettle();
    await saveScreenshot('add-menu');
  });
}
