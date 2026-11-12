import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'weekly_fake.dart';
import 'weekly_pump.dart';

void main() {
  testWidgets('dbg', (tester) async {
    final h = tester.ensureSemantics();
    final ps = [for (final (i, n) in ['Garden', 'Taxes', 'Garage'].indexed) lookBackProject('op$i', n, doneState: 'x', leftover: [{'id':'x$i','title':'T$n','due_day':'2030-02-26','planned_day':'2030-02-26'}])];
    await pumpWeekly(tester, WeeklyServer(lookBack: sampleLookBack(projects: ps)), size: const Size(1400, 2400));
    final n = tester.getSemantics(find.byKey(const Key('decision-recommit-op0')));
    print('LABEL: ${n.label}|${n.getSemanticsData().flagsCollection}');
    for (final k in ['op0','op1']) {
      print('CARD $k ${tester.getSize(find.byKey(Key('look-project-$k')))}');
    }
    h.dispose();
  });
}
