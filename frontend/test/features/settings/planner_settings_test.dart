import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/settings/planner_settings_card.dart';

import '../../support/fake_api.dart';

bool _on(WidgetTester tester) => tester
    .widget<SwitchListTile>(find.byKey(const Key('random-time-switch')))
    .value;

void main() {
  testWidgets('the switch is off by default and saves a change',
      (tester) async {
    var stored = false;
    final api = FakeApi({
      'GET /me/settings': (_) => {'random_time_on_date_drop': stored},
      'PATCH /me/settings': (o) {
        stored = (o.data as Map)['random_time_on_date_drop'] as bool;
        return {'random_time_on_date_drop': stored};
      },
    });
    await pumpWithApi(tester, api, const Scaffold(body: PlannerSettingsCard()));
    expect(_on(tester), isFalse);

    await tester.tap(find.byKey(const Key('random-time-switch')));
    await tester.pumpAndSettle();
    expect(api.where('PATCH /me/settings').single.data,
        {'random_time_on_date_drop': true});
    expect(_on(tester), isTrue); // reloaded from the server

    await tester.tap(find.byKey(const Key('random-time-switch')));
    await tester.pumpAndSettle();
    expect(_on(tester), isFalse);
  });

  testWidgets('a failed save shows the message and keeps the old value',
      (tester) async {
    final api = FakeApi({
      'GET /me/settings': {'random_time_on_date_drop': false},
      'PATCH /me/settings': const ApiFailure(500, 'Could not save.', 'error'),
    });
    await pumpWithApi(tester, api, const Scaffold(body: PlannerSettingsCard()));
    await tester.tap(find.byKey(const Key('random-time-switch')));
    await tester.pumpAndSettle();
    expect(find.text('Could not save.'), findsOneWidget);
    expect(_on(tester), isFalse);
  });

  testWidgets('a load error is shown with a retry button', (tester) async {
    final api = FakeApi({});
    await pumpWithApi(tester, api, const Scaffold(body: PlannerSettingsCard()));
    expect(find.byKey(const Key('planner-settings-error')), findsOneWidget);
  });

  testWidgets('the card keeps a readable width on a wide window',
      (tester) async {
    final api = FakeApi({
      'GET /me/settings': {'random_time_on_date_drop': false},
    });
    // pumpWithApi uses a 1000 wide surface; make it wider than a laptop screen
    await pumpWithApi(tester, api, const Scaffold(body: PlannerSettingsCard()));
    tester.view.physicalSize = const Size(1800, 1000);
    await tester.pumpAndSettle();
    final card = tester.getRect(find.byType(Card));
    expect(card.width, lessThanOrEqualTo(plannerSettingsCardWidth));
    expect(card.left, lessThan(40)); // sits at the left edge, not centered
  });
}
