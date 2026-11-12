import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/statistics/category_style.dart';
import 'package:tefteri/features/statistics/statistics_models.dart';
import 'package:tefteri/theme/theme.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance() + 0.05;
  final lb = b.computeLuminance() + 0.05;
  return la > lb ? la / lb : lb / la;
}

const _work = [Category.goalAligned, Category.maintenance, Category.offPlan];

Future<Map<Category, CategoryStyle>> _styles(
    WidgetTester tester, ThemeData theme) async {
  final out = <Category, CategoryStyle>{};
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    home: Builder(builder: (context) {
      for (final c in Category.values) {
        out[c] = categoryStyle(context, c);
      }
      return const SizedBox();
    }),
  ));
  return out;
}

void main() {
  for (final entry in {'light': tefteriLight, 'dark': tefteriDark}.entries) {
    group('in the ${entry.key} theme', () {
      testWidgets('the three styles differ in icon, fill and name',
          (tester) async {
        final s = await _styles(tester, entry.value);
        final styles = [for (final c in _work) s[c]!];
        // A greyscale render keeps the icon, the printed name and the shape of
        // the fill, so none of the three relies on color alone.
        expect({for (final x in styles) x.icon}, hasLength(3));
        expect({for (final x in styles) x.name}, hasLength(3));
        expect({
          for (final x in styles) '${x.hatched}-${x.outlineWidth}-${x.filled}'
        }, hasLength(3));
        expect(s[Category.goalAligned]!.filled, isTrue);
        expect(s[Category.goalAligned]!.hatched, isFalse);
        expect(s[Category.maintenance]!.hatched, isTrue);
        expect(s[Category.offPlan]!.filled, isFalse);
        expect(s[Category.offPlan]!.outlineWidth, 2);
        expect(styles.map((x) => x.name),
            ['Goal-aligned', 'Maintenance', 'Off-plan']);
      });

      testWidgets('the label reads on its fill (4.5 to 1)', (tester) async {
        final s = await _styles(tester, entry.value);
        for (final c in _work) {
          expect(_contrast(s[c]!.labelColor, s[c]!.background),
              greaterThanOrEqualTo(4.5),
              reason: '${s[c]!.name} label');
        }
      });
    });
  }

  testWidgets('each badge has a semantics label with the name and the count',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      theme: tefteriLight,
      home: const Column(children: [
        CategoryBadge(category: Category.goalAligned, count: 12),
        CategoryBadge(category: Category.maintenance, count: 1),
        CategoryBadge(category: Category.offPlan, count: 0),
      ]),
    ));
    expect(find.bySemanticsLabel('Goal-aligned: 12 tasks'), findsOneWidget);
    expect(find.bySemanticsLabel('Maintenance: 1 task'), findsOneWidget);
    expect(find.bySemanticsLabel('Off-plan: 0 tasks'), findsOneWidget);
    // The printed name is there too.
    expect(find.text('Goal-aligned'), findsOneWidget);
    expect(find.text('Off-plan'), findsOneWidget);
    handle.dispose();
  });
}
