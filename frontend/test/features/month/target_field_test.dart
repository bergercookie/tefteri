import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/month/target_field.dart';

void main() {
  testWidgets('accepts a whole number, empty none and explicit zero',
      (tester) async {
    final values = <int?>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TargetField(initialValue: null, onChanged: values.add),
      ),
    ));
    final field = find.byType(TextField);
    await tester.enterText(field, '12');
    expect(values.last, 12);
    await tester.enterText(field, '');
    expect(values.last, isNull);
    await tester.enterText(field, '0');
    expect(values.last, 0);
    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('rejects negative, decimal and text without saving',
      (tester) async {
    final values = <int?>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TargetField(initialValue: 3, onChanged: values.add),
      ),
    ));
    for (final invalid in ['-1', '2.5', 'abc']) {
      await tester.enterText(find.byType(TextField), invalid);
      await tester.pump();
      expect(find.textContaining('Use a whole number'), findsOneWidget);
      expect(values, isEmpty);
    }
    expect(find.textContaining('hours'), findsOneWidget);
    expect(find.textContaining('time'), findsOneWidget);
  });
}
