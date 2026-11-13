import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/annual/annual_screen.dart';

import '../../support/fake_api.dart';
import 'annual_fake.dart';

AnnualServer _server(Map<String, Object?> themes) => AnnualServer(
      goals: [
        annualGoalJson('g1', 'Get better at open source', keyResults: [
          keyResultJson('kr1', 'Stars',
              flags: [flagJson('no_usable_theme')], links: const []),
        ]),
      ],
      themes: themes,
    );

Object? _setThemes(RequestOptions o) {
  final body = o.data as Map;
  final ids = [...body['theme_ids'] as List];
  if (body['dry_run'] == true) {
    return {
      'effect': {
        'added': [
          for (final id in ids) {'project_id': id, 'name': 'Theme $id'}
        ],
        'ended': <Object?>[],
        'flags_removed': ['no_usable_theme'],
        'flags_added': <Object?>[],
      },
    };
  }
  return {
    'batch_id': 'b9',
    'key_result': keyResultJson('kr1', 'Stars',
        links: [for (final id in ids) linkJson('$id', 'Theme $id')]),
  };
}

Future<void> _openPicker(WidgetTester tester) =>
    menu(tester, 'kr-menu-kr1', 'Link themes');

void main() {
  testWidgets('only themes are listed, with a quiet note on unsorted ones',
      (tester) async {
    final server = _server(themesJson(
        themes: [themeJson('p1', 'Open source'), themeJson('p2', 'Talks')],
        unsorted: 5));
    final api = await pumpAnnual(tester,
        server.routes({'PUT /annual/key-results/kr1/themes': _setThemes}));
    await _openPicker(tester);
    expect(find.byKey(const Key('theme-option-p1')), findsOneWidget);
    expect(find.byKey(const Key('theme-option-p2')), findsOneWidget);
    expect(
        find.text('5 projects are unsorted. Unsorted projects can be '
            'classified first.'),
        findsOneWidget);
    await tapKey(tester, 'theme-option-p1');
    await tapKey(tester, 'themes-done');
    final puts = api.where('PUT /annual/key-results/kr1/themes');
    expect([for (final p in puts) (p.data! as Map)['dry_run']], [true, false]);
    expect((puts.last.data! as Map)['theme_ids'], ['p1']);
  });

  testWidgets(
      'an empty picker offers two inline actions that stay on the '
      'screen and never block the save', (tester) async {
    final server = _server(themesJson());
    final api = await pumpAnnual(
        tester,
        server.routes({
          'GET /projects/classification': {
            'connections': [
              {
                'connection_id': 'c1',
                'name': 'Vikunja',
                'status': 'ok',
                'last_sync_outcome': 'ok',
                'capabilities': {'rename': true, 'restore': true},
                'projects': [
                  classifiedJson('p3', 'Work'),
                  classifiedJson('p4', 'Old',
                      label: 'theme',
                      orphaned: {'reason': 'missing', 'at': null}),
                ],
              },
            ],
            'unsorted_count': 1,
          },
          'PUT /projects/labels': (RequestOptions o) {
            server.themes = themesJson(themes: [themeJson('p3', 'Work')]);
            return {
              'batch_id': 'lb1',
              'effect': {'changed': 1, 'by_change': <Object?>[]},
            };
          },
        }));
    await _openPicker(tester);
    expect(find.byKey(const Key('themes-empty')), findsOneWidget);
    final picker = find.byKey(const Key('theme-picker'));
    expect(
        find.descendant(
            of: picker, matching: find.text('Label a project as theme')),
        findsOneWidget);
    expect(find.descendant(of: picker, matching: find.text('Create a theme')),
        findsOneWidget);
    final done =
        tester.widget<ButtonStyleButton>(find.byKey(const Key('themes-done')));
    expect(done.onPressed, isNotNull);

    await tapKey(tester, 'picker-label-theme');
    expect(find.byType(AnnualScreen), findsOneWidget);
    expect(find.byKey(const Key('label-option-p3')), findsOneWidget);
    expect(find.byKey(const Key('label-option-p4')), findsNothing);
    await tapKey(tester, 'label-option-p3');
    final put = api.where('PUT /projects/labels').single.data! as Map;
    expect(put['changes'], [
      {'id': 'p3', 'label': 'theme'}
    ]);
    expect(find.byKey(const Key('theme-option-p3')), findsOneWidget);
  });

  testWidgets('create a theme: an existing name asks to link it instead',
      (tester) async {
    final server = _server(themesJson());
    final api = await pumpAnnual(
        tester,
        server.routes({
          'POST /annual/themes': const ApiFailure(
              409, 'A theme with this name exists.', 'theme_exists',
              extra: {
                'existing': {'project_id': 'p1', 'name': 'Open source'}
              }),
          'PUT /annual/key-results/kr1/themes': _setThemes,
        }));
    await _openPicker(tester);
    await tapKey(tester, 'picker-create-theme');
    await typeKey(tester, 'theme-name', 'Open source');
    await tapKey(tester, 'theme-create');
    expect(find.byKey(const Key('theme-exists-question')), findsOneWidget);
    expect(find.textContaining('Link the existing theme instead?'),
        findsOneWidget);
    await tapKey(tester, 'theme-link-existing');
    expect(find.byKey(const Key('create-theme-dialog')), findsNothing);
    await tapKey(tester, 'themes-done');
    final last =
        api.where('PUT /annual/key-results/kr1/themes').last.data! as Map;
    expect(last['theme_ids'], ['p1']);
  });

  testWidgets('a failed creation keeps the dialog open and stores nothing',
      (tester) async {
    final server = _server(themesJson());
    final api = await pumpAnnual(
        tester,
        server.routes({
          'POST /annual/themes': const ApiFailure(502,
              'Your task app did not answer. Nothing was stored.', 'not_saved'),
        }));
    await _openPicker(tester);
    await tapKey(tester, 'picker-create-theme');
    await typeKey(tester, 'theme-name', 'Talks');
    await tapKey(tester, 'theme-create');
    expect(find.byKey(const Key('create-theme-dialog')), findsOneWidget);
    expect(find.text('Your task app did not answer. Nothing was stored.'),
        findsOneWidget);
    expect(api.where('POST /annual/themes'), hasLength(1));
    expect(api.where('PUT /annual/key-results/kr1/themes'), isEmpty);
  });

  testWidgets('a new theme is offered and chosen at once', (tester) async {
    final server = _server(themesJson());
    final api = await pumpAnnual(
        tester,
        server.routes({
          'POST /annual/themes': (RequestOptions o) {
            server.themes = themesJson(themes: [themeJson('p7', 'Talks')]);
            return themeJson('p7', 'Talks');
          },
          'PUT /annual/key-results/kr1/themes': _setThemes,
        }));
    await _openPicker(tester);
    await tapKey(tester, 'picker-create-theme');
    await typeKey(tester, 'theme-name', 'Talks');
    await tapKey(tester, 'theme-create');
    expect((api.where('POST /annual/themes').single.data! as Map),
        {'connection_id': 'c1', 'name': 'Talks'});
    expect(find.byKey(const Key('theme-option-p7')), findsOneWidget);
    final box = tester.widget<Checkbox>(find.descendant(
        of: find.byKey(const Key('theme-option-p7')),
        matching: find.byType(Checkbox)));
    expect(box.value, isTrue);
  });

  testWidgets('the goal menu adds a theme to all its key results',
      (tester) async {
    final server = AnnualServer(
      goals: [
        annualGoalJson('g1', 'Get better at open source', keyResults: [
          keyResultJson('kr1', 'Stars'),
          keyResultJson('kr2', 'Talks given'),
        ]),
      ],
      themes: themesJson(themes: [themeJson('p1', 'Open source')]),
    );
    final api = await pumpAnnual(
        tester,
        server.routes({
          'PUT /annual/goals/g1/themes': (RequestOptions o) {
            return {'batch_id': 'b7', 'effect': <String, Object?>{}};
          },
        }));

    await menu(tester, 'goal-menu-g1', 'Link a theme to all key results');
    expect(find.byKey(const Key('theme-picker')), findsOneWidget);
    await tapKey(tester, 'theme-option-p1');
    await tapKey(tester, 'themes-done');

    final put = api.where('PUT /annual/goals/g1/themes').single;
    expect(put.data, {
      'theme_ids': ['p1']
    });
    expect(api.where('PUT /annual/key-results/kr1/themes'), isEmpty);
    expect(find.text('Theme added to 2 key results.'), findsOneWidget);
  });
}
