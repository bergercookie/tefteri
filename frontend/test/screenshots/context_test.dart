@Tags(['screenshots'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/core/context_filter.dart';
import 'package:tefteri/features/daily/daily_screen.dart';

import 'fixtures.dart';
import 'screenshot_helper.dart';

void main() {
  testWidgets('all/life/work switch and the unclassified marker',
      (tester) async {
    final view = dayView();
    final api = FakeApi({
      'GET /views/day/2026-11-02': {
        ...view,
        'entries': [(view['entries']! as List)[1]],
        'tasks': [
          taskJson('t2', 'Buy a birthday present', context: null),
          taskJson('t5', 'Water the plants', context: 'life'),
        ],
      },
      'GET /connections': connections,
    });
    await pumpScreen(tester, api, DailyScreen(initialDate: day), overrides: [
      contextFilterProvider.overrideWith((_) => ContextFilter.life),
    ]);
    await saveScreenshot('context-switch');
  });
}
