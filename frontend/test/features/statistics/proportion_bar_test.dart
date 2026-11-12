import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/statistics/proportion_bar.dart';
import 'package:tefteri/features/statistics/statistics_models.dart';
import 'package:tefteri/theme/theme.dart';

Future<void> _pump(WidgetTester tester, List<int> counts, List<int> pct,
    {double width = 400, ValueChanged<Category>? onSelect}) async {
  await tester.pumpWidget(MaterialApp(
    theme: tefteriLight,
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: ProportionBar(
            counts: CategoryCounts(counts[0], counts[1], counts[2]),
            percentages: CategoryCounts(pct[0], pct[1], pct[2]),
            onSelect: onSelect,
          ),
        ),
      ),
    ),
  ));
}

void main() {
  testWidgets('one category at 100 percent still names the other two',
      (tester) async {
    await _pump(tester, [0, 7, 0], [0, 100, 0]);
    expect(find.byKey(const Key('proportion-bar')), findsOneWidget);
    expect(find.byKey(const Key('bar-segment-maintenance')), findsOneWidget);
    expect(find.byKey(const Key('bar-segment-goal_aligned')), findsNothing);
    for (final name in ['Goal-aligned', 'Maintenance', 'Off-plan']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(
        find.descendant(
            of: find.byKey(const Key('bar-legend-goal_aligned')),
            matching: find.text('0')),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('bar-legend-maintenance')),
            matching: find.text('7')),
        findsOneWidget);
    // The one segment fills the bar.
    final bar = tester.getSize(find.byKey(const Key('proportion-bar')));
    final seg =
        tester.getSize(find.byKey(const Key('bar-segment-maintenance')));
    expect(seg.width, closeTo(bar.width, 0.5));
  });

  testWidgets('a segment of 1 percent is at least 6 logical pixels wide',
      (tester) async {
    await _pump(tester, [99, 0, 1], [99, 0, 1], width: 300);
    final small = tester.getSize(find.byKey(const Key('bar-segment-off_plan')));
    expect(small.width, greaterThanOrEqualTo(6));
    // Also when the share rounds down to nothing.
    await _pump(tester, [999, 0, 1], [100, 0, 0], width: 300);
    final tiny = tester.getSize(find.byKey(const Key('bar-segment-off_plan')));
    expect(tiny.width, greaterThanOrEqualTo(6));
    // The bar still fits its box.
    final big =
        tester.getSize(find.byKey(const Key('bar-segment-goal_aligned')));
    expect(big.width + tiny.width, lessThanOrEqualTo(300));
  });

  testWidgets('shows the percentages of the server, which add up to 100',
      (tester) async {
    await _pump(tester, [1, 1, 1], [34, 33, 33]);
    expect(find.text('34%'), findsOneWidget);
    expect(find.text('33%'), findsNWidgets(2));
  });

  testWidgets('a total of zero draws no bar', (tester) async {
    await _pump(tester, [0, 0, 0], [0, 0, 0]);
    expect(find.byKey(const Key('proportion-bar')), findsNothing);
  });

  testWidgets('the bar and each segment have a semantics label',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, [12, 5, 3], [60, 25, 15], onSelect: (_) {});
    expect(
        find.bySemanticsLabel(
            'Goal-aligned 12, maintenance 5, off-plan 3 tasks'),
        findsOneWidget);
    expect(find.bySemanticsLabel('Goal-aligned: 12 tasks, 60 percent'),
        findsOneWidget);
    expect(find.bySemanticsLabel('Maintenance: 5 tasks, 25 percent'),
        findsOneWidget);
    expect(
        find.bySemanticsLabel('Off-plan: 3 tasks, 15 percent'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a tap on a segment says which category', (tester) async {
    Category? picked;
    await _pump(tester, [12, 5, 3], [60, 25, 15], onSelect: (c) => picked = c);
    await tester.tap(find.byKey(const Key('bar-segment-maintenance')));
    expect(picked, Category.maintenance);
  });
}
