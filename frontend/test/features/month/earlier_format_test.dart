import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tefteri/features/month/month_screen.dart';

import '../../support/fake_api.dart';
import 'month_fake.dart';

void main() {
  testWidgets('old month goals appear in a read-only earlier-format view',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = MonthFakeApi(
      month: '2020-03',
      plan: monthlyJson(
        month: '2020-03',
        state: 'past',
        focusKnown: false,
        earlierFormat: true,
      ),
      legacyGoals: [
        {
          'id': 'g1',
          'title': 'Legacy goal',
          'description': 'Read-only notes',
          'criteria': 'Old success measure',
        },
      ],
    );
    await pumpWithApi(
        tester, api, MonthScreen(initialDate: DateTime(2020, 3, 10)));
    expect(find.byKey(const Key('earlier-format-view')), findsOneWidget);
    expect(find.text('Legacy goal'), findsOneWidget);
    expect(find.textContaining('read-only history'), findsOneWidget);
    expect(find.byKey(const Key('save-focus')), findsNothing);
    expect(find.byKey(const Key('choose-themes-empty')), findsNothing);
    expect(api.where('GET /goals/history').single.query, {
      'period_type': 'month',
      'period_start': '2020-03-01',
    });
  });
}
