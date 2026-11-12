import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/month/month_models.dart';
import 'package:tefteri/features/month/theme_picker.dart';

import '../../support/fake_api.dart';

Future<void> _pump(WidgetTester tester, FakeApi api,
    {List<MonthTheme> initial = const []}) async {
  await pumpWithApi(
    tester,
    api,
    Material(
      child: ThemePicker(
        month: '2030-03',
        initialSelection: initial,
        onSelectionChanged: (_) {},
      ),
    ),
  );
}

void main() {
  testWidgets('lists eligible themes grouped by connection and filters search',
      (tester) async {
    final themes = [
      for (var i = 0; i < 300; i++)
        monthlyThemeJson(
          'p$i',
          'Theme $i',
          connectionId: i % 2 == 0 ? 'c1' : 'c2',
          connectionName: i % 2 == 0 ? 'Work' : 'Home',
        ),
    ];
    await _pump(
      tester,
      FakeApi({
        'GET /monthly/2030-03/themes': monthlyPickerJson(themes: themes),
      }),
    );
    expect(find.text('Work'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Home'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Home'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('theme-search')), 'Theme 299');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('theme-option-p299')), findsOneWidget);
    expect(find.byKey(const Key('theme-option-p1')), findsNothing);
  });

  testWidgets('six themes show quiet guidance and remain selectable',
      (tester) async {
    final themes = [
      for (var i = 0; i < 6; i++) monthlyThemeJson('p$i', 'Theme $i'),
    ];
    var selected = <MonthTheme>[];
    await pumpWithApi(
      tester,
      FakeApi({
        'GET /monthly/2030-03/themes': monthlyPickerJson(themes: themes),
      }),
      Material(
        child: ThemePicker(
          month: '2030-03',
          initialSelection: const [],
          onSelectionChanged: (value) => selected = value,
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.tap(find.byKey(Key('theme-option-p$i')));
    }
    expect(find.byKey(const Key('focus-size-note')), findsOneWidget);
    expect(selected, hasLength(6));
    expect(find.textContaining('Three to five'), findsOneWidget);
  });

  testWidgets('empty picker labels and creates a theme in place',
      (tester) async {
    final api = FakeApi({
      'GET /monthly/2030-03/themes': monthlyPickerJson(themes: []),
      'GET /projects/classification': {
        'unsorted_count': 1,
        'connections': [
          {
            'connection_id': 'c1',
            'name': 'Work',
            'projects': [classifiedJson('u1', 'Unsorted')],
          },
        ],
      },
      'PUT /projects/labels': {
        'batch_id': 'b1',
        'effect': {'changed': 1},
      },
      'POST /annual/themes': {'id': 'created'},
    });
    await _pump(tester, api);
    expect(
      find.text(
          'A theme project is a long-running home for related work. Label a project or create a theme to add one here.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('label-project-as-theme')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unsorted'));
    await tester.pumpAndSettle();
    expect(api.where('PUT /projects/labels'), hasLength(1));
    expect(find.byKey(const Key('create-theme')), findsOneWidget);

    await tester.tap(find.byKey(const Key('create-theme')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'New theme');
    await tester.tap(find.text('Create theme').last);
    await tester.pumpAndSettle();
    expect(api.where('POST /annual/themes'), hasLength(1));
    expect(find.byKey(const Key('label-project-as-theme')), findsOneWidget);
  });

  testWidgets('inline actions preserve the themes already selected',
      (tester) async {
    final api = FakeApi({
      'GET /monthly/2030-03/themes': monthlyPickerJson(themes: []),
      'GET /projects/classification': {
        'unsorted_count': 1,
        'connections': [
          {
            'connection_id': 'c1',
            'name': 'Work',
            'projects': [classifiedJson('u1', 'Unsorted')],
          },
        ],
      },
      'PUT /projects/labels': {
        'batch_id': 'b1',
        'effect': {'changed': 1},
      },
    });
    final selected = MonthTheme.fromJson(monthlyThemeJson('p1', 'Kept theme'));
    await _pump(tester, api, initial: [selected]);
    expect(find.text('Still selected: Kept theme'), findsOneWidget);
    await tester.tap(find.byKey(const Key('label-project-as-theme')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unsorted'));
    await tester.pumpAndSettle();
    expect(find.text('Still selected: Kept theme'), findsOneWidget);
  });
}
