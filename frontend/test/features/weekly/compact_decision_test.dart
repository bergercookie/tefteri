import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/weekly/weekly_models.dart';

import '../../screenshots/screenshot_helper.dart' show loadFonts;
import 'weekly_fake.dart';
import 'weekly_pump.dart';

List<Map<String, Object?>> _three() => [
      for (final (i, n) in ['Garden', 'Taxes', 'Garage'].indexed)
        lookBackProject('op$i', n, doneState: 'It is finished', leftover: [
          {
            'id': 'x$i',
            'title': 'Task $n',
            'due_day': '2030-02-26',
            'planned_day': '2030-02-26'
          },
        ]),
    ];

Future<void> _pump(WidgetTester tester,
    {Size size = const Size(1000, 2400),
    Brightness brightness = Brightness.light}) async {
  final s = WeeklyServer(lookBack: sampleLookBack(projects: _three()));
  await pumpWeekly(tester, s, size: size, brightness: brightness);
}

void main() {
  testWidgets('every chip has a clear label and selecting one is announced',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    for (final d in Decision.values) {
      expect(find.bySemanticsLabel('${d.label} for Garden'), findsOneWidget,
          reason: d.label);
    }
    await tapKey(tester, 'decision-recommit-op0');
    final node = tester
        .getSemantics(find.bySemanticsLabel('Keep and recommit for Garden'));
    expect(node.label, 'Keep and recommit for Garden');
    final data = node.getSemanticsData();
    expect(data.flagsCollection.isSelected, Tristate.isTrue);
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    handle.dispose();
  });

  testWidgets('the explanation follows the selection', (tester) async {
    await _pump(tester);
    expect(
        find.text('Choose what happens to this milestone.'), findsNWidgets(3));
    await tapKey(tester, 'decision-decide_later-op1');
    expect(find.text(Decision.decideLater.sentence), findsOneWidget);
    expect(
        find.text('Choose what happens to this milestone.'), findsNWidgets(2));
    await tapKey(tester, 'decision-recommit-op1');
    expect(find.text(Decision.decideLater.sentence), findsNothing);
    expect(find.text(Decision.recommit.sentence), findsOneWidget);
    expect(find.byKey(const Key('expected-op1')), findsOneWidget);
  });

  testWidgets('three unfinished milestones stay compact on desktop',
      (tester) async {
    // Real fonts: the test font is much wider and would make text wrap.
    await loadFonts();
    await _pump(tester, size: const Size(1400, 2400));
    final top = tester.getTopLeft(find.byKey(const Key('look-project-op0'))).dy;
    final bottom =
        tester.getBottomLeft(find.byKey(const Key('look-project-op2'))).dy;
    expect(bottom - top, lessThan(1000));
  });

  for (final b in [Brightness.light, Brightness.dark]) {
    testWidgets('no overflow at 360 px wide in ${b.name}', (tester) async {
      await _pump(tester, size: const Size(360, 2400), brightness: b);
      expect(tester.takeException(), isNull);
      for (final d in Decision.values) {
        expect(find.byKey(Key('decision-${d.api}-op0')), findsOneWidget);
      }
      await tapKey(tester, 'decision-recommit-op0');
      expect(tester.takeException(), isNull);
    });
  }
}
