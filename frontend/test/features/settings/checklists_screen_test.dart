import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/settings/checklists_screen.dart';

import '../../support/fake_api.dart';

Map<String, Object?> _settings(
        {List<String> week = const [],
        List<String> month = const [],
        List<String> year = const []}) =>
    {
      'random_time_on_date_drop': false,
      'default_reminder_minutes': 15,
      'checklists': {'week': week, 'month': month, 'year': year},
    };

String _box(WidgetTester tester, String kind) => tester
    .widget<TextField>(find.byKey(Key('checklist-box-$kind')))
    .controller!
    .text;

String _count(WidgetTester tester, String kind) =>
    tester.widget<Text>(find.byKey(Key('checklist-count-$kind'))).data!;

bool _canSave(WidgetTester tester) => tester
    .widget<FilledButton>(find.byKey(const Key('checklists-save')))
    .enabled;

Future<void> _type(WidgetTester tester, String kind, String text) async {
  final f = find.byKey(Key('checklist-box-$kind'));
  await tester.ensureVisible(f);
  await tester.enterText(f, text);
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  final f = find.byKey(const Key('checklists-save'));
  await tester.ensureVisible(f);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the three lists, one item on each line', (tester) async {
    await pumpWithApi(
        tester,
        FakeApi({
          'GET /me/settings': _settings(
              week: ['Clear the inbox', 'Check goals'], month: ['Bills']),
        }),
        const ChecklistsScreen());
    expect(find.text('Weekly checklist'), findsOneWidget);
    expect(find.text('Monthly checklist'), findsOneWidget);
    expect(find.text('Annual checklist'), findsOneWidget);
    expect(_box(tester, 'week'), 'Clear the inbox\nCheck goals');
    expect(_box(tester, 'month'), 'Bills');
    expect(_box(tester, 'year'), '');
    expect(_count(tester, 'week'), '2 items');
    expect(_count(tester, 'month'), '1 item');
    expect(_count(tester, 'year'), contains('no annual checklist'));
    expect(_canSave(tester), isFalse); // nothing changed yet
  });

  testWidgets('a change is counted, and only the changed list is saved',
      (tester) async {
    var stored = _settings(week: ['Clear the inbox'], month: ['Bills']);
    final api = FakeApi({
      'GET /me/settings': (_) => stored,
      'PATCH /me/settings': (o) {
        final sent = (o.data as Map)['checklists'] as Map;
        stored = _settings(
          week: [...?(sent['week'] as List?)?.cast<String>()],
          month: ['Bills'],
        );
        return stored;
      },
    });
    await pumpWithApi(tester, api, const ChecklistsScreen());

    await _type(
        tester, 'week', 'Clear the inbox\nCheck goals\n\nPlan the days');
    expect(_count(tester, 'week'), '3 items, not saved yet');
    expect(_canSave(tester), isTrue);

    await _save(tester);
    expect(api.where('PATCH /me/settings').single.data, {
      'checklists': {
        'week': ['Clear the inbox', 'Check goals', 'Plan the days'],
      },
    });
    expect(find.byKey(const Key('checklists-saved')), findsOneWidget);
    expect(_count(tester, 'week'), '3 items');
    expect(_canSave(tester), isFalse);
  });

  testWidgets('editing the box again hides the saved note', (tester) async {
    final api = FakeApi({
      'GET /me/settings': _settings(week: ['a']),
      'PATCH /me/settings': _settings(week: ['a', 'b']),
    });
    await pumpWithApi(tester, api, const ChecklistsScreen());
    await _type(tester, 'week', 'a\nb');
    await _save(tester);
    expect(find.byKey(const Key('checklists-saved')), findsOneWidget);
    await _type(tester, 'week', 'a\nb\nc');
    expect(find.byKey(const Key('checklists-saved')), findsNothing);
  });

  testWidgets('removing every line removes the checklist', (tester) async {
    final api = FakeApi({
      'GET /me/settings': _settings(week: ['a', 'b']),
      'PATCH /me/settings': _settings(),
    });
    await pumpWithApi(tester, api, const ChecklistsScreen());
    await _type(tester, 'week', '');
    await _save(tester);
    expect(api.where('PATCH /me/settings').single.data, {
      'checklists': {'week': <String>[]},
    });
    expect(_box(tester, 'week'), '');
  });

  testWidgets('a pasted list with bullets and repeats is cleaned',
      (tester) async {
    await pumpWithApi(tester, FakeApi({'GET /me/settings': _settings()}),
        const ChecklistsScreen());
    await _type(
        tester, 'month', '- Pay the bills\n* pay the bills\n[ ] Archive\n');
    expect(_count(tester, 'month'), '2 items, not saved yet');
  });

  testWidgets('an example fills an empty list, and is not saved until Save',
      (tester) async {
    final api = FakeApi({
      'GET /me/settings': _settings(month: ['Bills']),
    });
    await pumpWithApi(tester, api, const ChecklistsScreen());
    // Only the empty lists offer an example.
    expect(find.byKey(const Key('checklist-example-week')), findsOneWidget);
    expect(find.byKey(const Key('checklist-example-month')), findsNothing);

    await tester.ensureVisible(find.byKey(const Key('checklist-example-week')));
    await tester.tap(find.byKey(const Key('checklist-example-week')));
    await tester.pumpAndSettle();
    expect(_box(tester, 'week').split('\n'), checklistExamples.values.first);
    expect(_canSave(tester), isTrue);
    expect(api.where('PATCH /me/settings'), isEmpty);
    expect(find.byKey(const Key('checklist-example-week')), findsNothing);
  });

  testWidgets('too many items cannot be saved', (tester) async {
    await pumpWithApi(tester, FakeApi({'GET /me/settings': _settings()}),
        const ChecklistsScreen());
    await _type(
        tester, 'week', [for (var i = 0; i < 51; i++) 'Item $i'].join('\n'));
    expect(find.textContaining('At most 50 items'), findsOneWidget);
    expect(_canSave(tester), isFalse);
    await _type(
        tester, 'week', [for (var i = 0; i < 50; i++) 'Item $i'].join('\n'));
    expect(_canSave(tester), isTrue);
  });

  testWidgets('a failed save shows the message and keeps what was typed',
      (tester) async {
    final api = FakeApi({
      'GET /me/settings': _settings(week: ['a']),
      'PATCH /me/settings': const ApiFailure(500, 'Could not save.', 'error'),
    });
    await pumpWithApi(tester, api, const ChecklistsScreen());
    await _type(tester, 'week', 'a\nb');
    await _save(tester);
    expect(find.text('Could not save.'), findsOneWidget);
    expect(_box(tester, 'week'), 'a\nb');
    expect(_canSave(tester), isTrue); // it can be tried again
  });

  testWidgets('a load error has a retry button', (tester) async {
    await pumpWithApi(tester, FakeApi({}), const ChecklistsScreen());
    expect(find.byKey(const Key('checklists-load-error')), findsOneWidget);
    expect(find.byKey(const Key('checklists-retry')), findsOneWidget);
  });
}
