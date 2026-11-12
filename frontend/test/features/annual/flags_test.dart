import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_api.dart';
import 'annual_fake.dart';

AnnualServer _flagged() => AnnualServer(goals: [
      annualGoalJson('g1', 'Read more books'),
      annualGoalJson('g2', 'Get better at open source', keyResults: [
        keyResultJson('kr1', 'Stars', start: 120, target: 500, links: [
          linkJson('p1', 'Open source',
              usable: false, state: 'ignored', label: 'theme'),
        ], flags: [
          flagJson('no_usable_theme', reasons: [
            {
              'project_id': 'p1',
              'name': 'Open source',
              'state': 'ignored',
              'label': 'theme'
            },
          ]),
        ]),
        keyResultJson('kr2', 'Talks',
            start: 0,
            target: 2,
            deadline: '2030-02-28',
            links: [linkJson('p2', 'Talks')],
            flags: [flagJson('overdue')]),
      ]),
    ]);

double _contrast(Color a, Color b) {
  final la = a.computeLuminance() + 0.05;
  final lb = b.computeLuminance() + 0.05;
  return la > lb ? la / lb : lb / la;
}

void main() {
  testWidgets('the three flags show their reason and inline actions',
      (tester) async {
    await pumpAnnual(tester, _flagged().routes());
    final none = find.byKey(const Key('flag-no_key_result-g1'));
    expect(none, findsOneWidget);
    expect(find.descendant(of: none, matching: find.text('Add key result')),
        findsOneWidget);

    final theme = find.byKey(const Key('flag-no_usable_theme-kr1'));
    expect(theme, findsOneWidget);
    expect(
        find.descendant(
            of: theme, matching: find.text('"Open source" is ignored.')),
        findsOneWidget);
    expect(find.descendant(of: theme, matching: find.text('Link a theme')),
        findsOneWidget);
    expect(find.descendant(of: theme, matching: find.text('Create a theme')),
        findsOneWidget);

    final overdue = find.byKey(const Key('flag-overdue-kr2'));
    expect(overdue, findsOneWidget);
    expect(find.descendant(of: overdue, matching: find.text('Update value')),
        findsOneWidget);
  });

  testWidgets('the inline actions open the right dialog', (tester) async {
    final server = _flagged();
    await pumpAnnual(tester, server.routes());
    await tapKey(tester, 'flag-action-add_key_result-g1');
    expect(find.byKey(const Key('kr-form')), findsOneWidget);
    await tapKey(tester, 'kr-cancel');
    await tapKey(tester, 'flag-action-link_theme-kr1');
    expect(find.byKey(const Key('theme-picker')), findsOneWidget);
    await tapKey(tester, 'themes-cancel');
    await tapKey(tester, 'flag-action-create_theme-kr1');
    expect(find.byKey(const Key('create-theme-dialog')), findsOneWidget);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    // The picker stays open under the create dialog.
    await tapKey(tester, 'themes-cancel');
    await tapKey(tester, 'flag-action-update_value-kr2');
    expect(find.byKey(const Key('value-dialog')), findsOneWidget);
  });

  testWidgets('no flag disables a save', (tester) async {
    await pumpAnnual(tester, _flagged().routes());
    final add =
        tester.widget<ButtonStyleButton>(find.byKey(const Key('add-goal')));
    expect(add.onPressed, isNotNull);
    await tapKey(tester, 'add-kr-g1');
    final save =
        tester.widget<ButtonStyleButton>(find.byKey(const Key('kr-save')));
    expect(save.onPressed, isNotNull);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('flags are readable in ${mode.name} mode', (tester) async {
      await pumpAnnual(tester, _flagged().routes(), themeMode: mode);
      for (final key in [
        'flag-no_key_result-g1',
        'flag-no_usable_theme-kr1',
        'flag-overdue-kr2'
      ]) {
        final box = tester.widget<Container>(find.byKey(Key(key)));
        final bg = (box.decoration! as BoxDecoration).color!;
        final title = tester.widget<Text>(find.byKey(Key('$key-title')));
        expect(_contrast(title.style!.color!, bg), greaterThan(4.5),
            reason: key);
      }
    });
  }
}
