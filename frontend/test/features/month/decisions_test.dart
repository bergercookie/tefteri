import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/month/theme_decision_card.dart';

import '../../support/fake_api.dart';
import 'month_fake.dart';

void main() {
  testWidgets('carry, drop and decide later show an effect before saving',
      (tester) async {
    final api = MonthFakeApi();
    final decisions = <String>[];
    await pumpWithApi(
      tester,
      api,
      Material(
        child: ThemeDecisionCard(
          month: '2030-03',
          theme: monthlyReviewThemeJson(projectId: 'p1', name: 'Open source'),
          initialDecision: 'later',
          onChanged: (decision, {replacementProjectId}) {
            decisions.add(decision);
          },
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('decision-p1-carry')));
    await tester.pumpAndSettle();
    expect(find.textContaining('will be offered next month'), findsOneWidget);
    expect(decisions, isEmpty);
    await tester.tap(find.byKey(const Key('confirm-theme-decision')));
    await tester.pumpAndSettle();
    expect(decisions, ['carry']);

    await tester.tap(find.byKey(const Key('decision-p1-drop')));
    await tester.pumpAndSettle();
    expect(find.textContaining('will not be suggested'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-theme-decision')));
    await tester.pumpAndSettle();
    expect(decisions.last, 'drop');

    await tester.tap(find.byKey(const Key('undo-decision-p1')));
    await tester.pumpAndSettle();
    expect(decisions.last, 'later');
    await tester.tap(find.byKey(const Key('decision-p1-later')));
    await tester.pumpAndSettle();
    expect(find.textContaining('decide what to do'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-theme-decision')));
    await tester.pumpAndSettle();
    expect(decisions.last, 'later');
  });

  testWidgets('replace asks for a live theme and distinguishes swap',
      (tester) async {
    final api = MonthFakeApi();
    String? replacement;
    await pumpWithApi(
      tester,
      api,
      Material(
        child: ThemeDecisionCard(
          month: '2030-03',
          theme: monthlyReviewThemeJson(projectId: 'p1', name: 'Open source'),
          initialDecision: 'later',
          onChanged: (decision, {replacementProjectId}) {
            replacement = replacementProjectId;
          },
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('decision-p1-replace')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('replace-theme-p2')));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('Replace is a month-end decision'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-theme-decision')));
    await tester.pumpAndSettle();
    expect(replacement, 'p2');
    expect(api.where('GET /monthly/2030-03/themes'), hasLength(1));
  });
}
