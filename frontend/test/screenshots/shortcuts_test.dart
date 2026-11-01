@Tags(['screenshots'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/daily/daily_screen.dart';

import 'fixtures.dart';
import 'screenshot_helper.dart';

void main() {
  testWidgets('shortcut help overlay', (tester) async {
    final api = FakeApi({
      'GET /views/day/2026-11-02': dayView(),
      'GET /connections': connections,
    });
    await pumpScreen(tester, api, DailyScreen(initialDate: day),
        size: const Size(1100, 1000));
    await tester.tap(find.byKey(const Key('shortcuts-button')));
    await tester.pumpAndSettle();
    await saveScreenshot('shortcuts-help');
  });
}
