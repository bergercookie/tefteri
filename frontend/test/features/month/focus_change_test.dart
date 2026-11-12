import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tefteri/features/month/month_screen.dart';

import '../../support/fake_api.dart';
import 'month_fake.dart';

Future<void> _pump(WidgetTester tester, MonthFakeApi api) async {
  SharedPreferences.setMockInitialValues({});
  await pumpWithApi(
      tester, api, MonthScreen(initialDate: DateTime(2030, 3, 10)));
}

void main() {
  testWidgets('remove previews effect, applies only on confirm and offers undo',
      (tester) async {
    final api = MonthFakeApi();
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('remove-theme-p1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('focus-change-effect')), findsOneWidget);
    expect(api.where('POST /monthly/2030-03/changes').single.data,
        containsPair('dry_run', true));
    await tester.tap(find.byKey(const Key('focus-change-confirm')));
    await tester.pumpAndSettle();
    expect(api.where('POST /monthly/2030-03/changes'), hasLength(2));
    expect(find.byKey(const Key('focus-undo-snackbar')), findsOneWidget);
    await tester.tap(find.descendant(
      of: find.byKey(const Key('focus-undo-snackbar')),
      matching: find.text('Undo'),
    ));
    await tester.pumpAndSettle();
    expect(api.where('POST /monthly/2030-03/changes/undo'), hasLength(1));
    expect(find.byKey(const Key('focus-history')), findsOneWidget);
  });

  testWidgets('cancel keeps the focus and target changes preview first',
      (tester) async {
    final api = MonthFakeApi();
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('remove-theme-p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('focus-change-cancel')));
    await tester.pumpAndSettle();
    expect(api.where('POST /monthly/2030-03/changes'), hasLength(1));
    expect(find.text('Open source'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('target-p1')), '4');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('apply-target-changes')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('focus-change-effect')), findsOneWidget);
    expect(api.where('POST /monthly/2030-03/changes').last.data,
        containsPair('kind', 'target'));
  });

  testWidgets('swap picker explains the action and history can undo',
      (tester) async {
    final api = MonthFakeApi();
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('swap-theme-p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('theme-option-p2')));
    await tester.tap(find.byKey(const Key('theme-picker-done')));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('Replace is a month-end decision'), findsOneWidget);
    await tester.tap(find.byKey(const Key('focus-change-confirm')));
    await tester.pumpAndSettle();
    expect(api.where('POST /monthly/2030-03/changes'), hasLength(2));

    await tester.tap(find.byKey(const Key('focus-history')));
    await tester.pumpAndSettle();
    expect(find.text('2030-03-14 · swap'), findsOneWidget);
    expect(find.byKey(const Key('undo-change-batch-1')), findsOneWidget);
  });

  testWidgets('a theme that left cannot be added again without undo',
      (tester) async {
    final api = MonthFakeApi();
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('remove-theme-p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('focus-change-confirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('choose-themes-empty')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Undo that change before adding it again'),
        findsOneWidget);
    expect(
      tester.widget<InkWell>(find.byKey(const Key('theme-option-p1'))).onTap,
      isNull,
    );
  });

  testWidgets('adding a theme also shows its effect before confirmation',
      (tester) async {
    final api = MonthFakeApi(
      plan: monthlyJson(
        entries: const [],
        focusKnown: true,
        state: 'current',
      ),
    );
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('choose-themes-empty')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('theme-option-p2')));
    await tester.tap(find.byKey(const Key('theme-picker-done')));
    await tester.pumpAndSettle();
    expect(api.where('POST /monthly/2030-03/changes').single.data,
        containsPair('dry_run', true));
    await tester.tap(find.byKey(const Key('focus-change-confirm')));
    await tester.pumpAndSettle();
    expect(
      (api.where('POST /monthly/2030-03/changes').last.data as Map)['kind'],
      'add',
    );
  });
}
