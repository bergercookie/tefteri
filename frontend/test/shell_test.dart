import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/core/context_filter.dart';
import 'package:tefteri/core/shell.dart';

void main() {
  testWidgets('context switch updates the global filter', (tester) async {
    final container = ProviderContainer();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AppShell(title: 'T', body: SizedBox())),
    ));
    await tester.tap(find.text('work'));
    await tester.pump();
    expect(container.read(contextFilterProvider), ContextFilter.work);
    expect(find.byKey(const Key('sync-button')), findsOneWidget);
  });
}
