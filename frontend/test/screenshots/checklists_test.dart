@Tags(['screenshots'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/settings/checklists_screen.dart';

import 'screenshot_helper.dart';

void main() {
  testWidgets('checklists in the settings', (tester) async {
    await pumpScreen(
      tester,
      FakeApi({
        'GET /me/settings': {
          'random_time_on_date_drop': false,
          'default_reminder_minutes': 15,
          'checklists': {
            'week': checklistExamples.values.first,
            'month': checklistExamples.values.elementAt(1),
            'year': <String>[],
          },
        },
      }),
      const ChecklistsScreen(),
      size: const Size(1100, 900),
    );
    await saveScreenshot('settings-checklists');
  });
}
