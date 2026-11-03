@Tags(['screenshots'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/core/api_client.dart';
import 'package:tefteri/features/settings/connection_models.dart';
import 'package:tefteri/features/settings/connections_screen.dart';
import 'package:tefteri/features/settings/sync_controller.dart';

import 'fixtures.dart';
import 'screenshot_helper.dart';

Map<String, Object?> _result(String id, String name, String outcome,
        [String? reason]) =>
    {
      'connection_id': id,
      'name': name,
      'outcome': outcome,
      'reason': reason,
      'counts': {'created': 0, 'updated': 3},
    };

FakeApi _api(List<Object?> results) => FakeApi({
      'GET /connections': connections,
      'GET /sync/status': {
        'last_sync_at': '2026-11-02T08:15:00Z',
        'results': []
      },
      'POST /sync': results,
      'GET /me/settings': {'random_time_on_date_drop': false},
    });

/// Uses a fixed sync time, so the image does not change with the clock.
class _FixedTimeSync extends SyncController {
  _FixedTimeSync(this._r) : super(_r);

  final Ref _r;

  @override
  Future<void> syncAll() async {
    state = const SyncState(busy: true, announce: true);
    final r = await _r.read(dioProvider).post<Object?>('/sync');
    state = SyncState(
      announce: true,
      results: {for (final x in parseSyncResults(r.data)) x.connectionId: x},
      lastSyncAt: DateTime(2026, 11, 2, 8, 15),
    );
  }
}

final _fixedTime = [syncControllerProvider.overrideWith(_FixedTimeSync.new)];

void main() {
  testWidgets('planner setting: random time for date-only drops',
      (tester) async {
    final api = FakeApi({
      'GET /connections': connections,
      'GET /sync/status': {
        'last_sync_at': '2026-11-02T08:15:00Z',
        'results': []
      },
      'GET /me/settings': {'random_time_on_date_drop': true},
    });
    await pumpScreen(tester, api, const ConnectionsScreen());
    await saveScreenshot('planner-setting-random-time');
  });

  testWidgets('connections list', (tester) async {
    await pumpScreen(tester, _api([]), const ConnectionsScreen());
    await saveScreenshot('connections-list');
  });

  testWidgets('sync result', (tester) async {
    await pumpScreen(
        tester,
        _api([
          _result('c1', 'Home tasks', 'ok'),
          _result('c2', 'Work calendar', 'ok'),
          _result('c3', 'Notes', 'ok'),
        ]),
        const ConnectionsScreen(),
        overrides: _fixedTime);
    await tester.tap(find.byKey(const Key('sync-button')));
    await tester.pumpAndSettle();
    await saveScreenshot('connections-sync-result');
  });

  testWidgets('unavailable apps', (tester) async {
    await pumpScreen(
        tester,
        _api([
          _result('c1', 'Home tasks', 'error', 'unreachable'),
          _result('c2', 'Work calendar', 'needs_attention', 'auth_expired'),
          _result('c3', 'Notes', 'ok'),
        ]),
        const ConnectionsScreen(),
        overrides: _fixedTime);
    await tester.tap(find.byKey(const Key('sync-all-button')));
    await tester.pumpAndSettle();
    await saveScreenshot('connections-unavailable');
  });
}
