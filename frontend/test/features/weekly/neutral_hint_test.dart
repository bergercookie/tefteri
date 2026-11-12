import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/weekly/weekly_widgets.dart';
import 'package:tefteri/theme/theme.dart';

void main() {
  for (final theme in [tefteriLight, tefteriDark]) {
    testWidgets('a Notice is neutral, not painted in the alert tint',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: const Scaffold(body: Notice(message: 'Add a task here.')),
      ));
      final box = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((d) => d.border != null);
      expect(box.color, theme.colorScheme.surfaceContainerLow);
      expect(box.color, isNot(theme.extension<TefteriColors>()!.taskContainer));
      expect(box.color, isNot(theme.colorScheme.errorContainer));
    });
  }
}
