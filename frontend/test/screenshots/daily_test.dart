@Tags(['screenshots'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/daily/daily_screen.dart';

import 'fixtures.dart';
import 'screenshot_helper.dart';

FakeApi _api() => FakeApi({
      'GET /views/day/2026-11-02': dayView(),
      'GET /connections': connections,
    });

void main() {
  testWidgets('daily view', (tester) async {
    await pumpScreen(tester, _api(), DailyScreen(initialDate: day));
    await saveScreenshot('daily-view');
  });

  testWidgets('quick add', (tester) async {
    await pumpScreen(tester, _api(), DailyScreen(initialDate: day));
    await tester.enterText(
        find.byKey(const Key('quick-add-field')), 'Book the train tickets');
    await tester.pumpAndSettle();
    await saveScreenshot('daily-quick-add');
  });
}
