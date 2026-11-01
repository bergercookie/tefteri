import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/conflicts/conflicts_screen.dart';

import '../../support/fake_api.dart';

final _conflict = {
  'id': 'k1',
  'entity_type': 'task',
  'entity_id': 't1',
  'local_snapshot': {'title': 'Write report', 'status': 'open'},
  'remote_snapshot': {'title': 'Write final report', 'status': 'open'},
  'created_at': '2026-11-01T09:00:00Z',
};

void main() {
  testWidgets('shows both versions', (tester) async {
    final api = FakeApi({
      'GET /conflicts': [_conflict]
    });
    await pumpWithApi(tester, api, const ConflictsScreen());
    expect(find.text('Your version'), findsOneWidget);
    expect(find.text('Other app version'), findsOneWidget);
    expect(find.text('title: Write report'), findsOneWidget);
    expect(find.text('title: Write final report'), findsOneWidget);
  });

  testWidgets('keep your version posts keep_local and reloads', (tester) async {
    final api = FakeApi({
      'GET /conflicts': [_conflict],
      'POST /conflicts/k1/resolve': const NoContent(),
    });
    await pumpWithApi(tester, api, const ConflictsScreen());
    await tester.tap(find.byKey(const Key('keep-local-k1')));
    await tester.pumpAndSettle();
    expect(api.where('POST /conflicts/k1/resolve').single.data,
        {'resolution': 'keep_local'});
    expect(api.where('GET /conflicts'), hasLength(2));
  });

  testWidgets('keep other app version posts keep_remote', (tester) async {
    final api = FakeApi({
      'GET /conflicts': [_conflict],
      'POST /conflicts/k1/resolve': const NoContent(),
    });
    await pumpWithApi(tester, api, const ConflictsScreen());
    await tester.tap(find.byKey(const Key('keep-remote-k1')));
    await tester.pumpAndSettle();
    expect(api.where('POST /conflicts/k1/resolve').single.data,
        {'resolution': 'keep_remote'});
  });

  testWidgets('a failed resolve shows the detail', (tester) async {
    final api = FakeApi({
      'GET /conflicts': [_conflict],
      'POST /conflicts/k1/resolve': const ApiFailure(
          502, 'Home tasks is not reachable.', 'backend_unavailable'),
    });
    await pumpWithApi(tester, api, const ConflictsScreen());
    await tester.tap(find.byKey(const Key('keep-local-k1')));
    await tester.pumpAndSettle();
    expect(find.text('Home tasks is not reachable.'), findsOneWidget);
    expect(find.byKey(const Key('conflict-k1')), findsOneWidget);
  });

  testWidgets('empty list shows a message', (tester) async {
    await pumpWithApi(
        tester, FakeApi({'GET /conflicts': []}), const ConflictsScreen());
    expect(find.text('No conflicts.'), findsOneWidget);
  });
}
