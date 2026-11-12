import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/month/month_models.dart';
import 'package:tefteri/features/month/suggestions_card.dart';

import '../../support/fake_api.dart';

void main() {
  testWidgets('carried-forward suggestions are editable and unsaved',
      (tester) async {
    final suggestions = MonthSuggestions.fromJson(monthlySuggestionsJson(
      fromMonth: '2030-02',
      suggestions: [
        monthlySuggestionJson('p1', 'Open source', target: 3),
        monthlySuggestionJson('p2', 'Research'),
      ],
    ));
    List<MonthSuggestion> selected = [];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SuggestionsCard(
          suggestions: suggestions,
          onChanged: (value) => selected = value,
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('Suggestions from 2030-02'), findsOneWidget);
    expect(find.textContaining('not saved until you choose Save.'),
        findsOneWidget);
    await tester.enterText(find.byKey(const Key('suggestion-target-p1')), '5');
    await tester.pump();
    expect(selected.first.target, 5);
    await tester.tap(find.byKey(const Key('remove-suggestion-p2')));
    await tester.pump();
    expect(selected.map((item) => item.projectId), ['p1']);
    expect(find.text('Open source'), findsOneWidget);
  });
}
