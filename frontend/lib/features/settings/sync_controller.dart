/// Shared state and actions for syncing and listing connections.
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'connection_models.dart';

/// State of the sync controller.
@immutable
class SyncState {
  /// Creates a state.
  const SyncState({
    this.busy = false,
    this.results = const {},
    this.error,
    this.lastSyncAt,
  });

  /// True while a sync request runs.
  final bool busy;

  /// Latest result per connection id.
  final Map<String, SyncResult> results;

  /// Message when the sync request itself failed; null otherwise.
  final String? error;

  /// Time of the last sync, from the server when known.
  final DateTime? lastSyncAt;

  /// Results that failed.
  List<SyncResult> get failures =>
      results.values.where((r) => r.failed).toList();

  /// Returns a copy with changed fields. [error] is always replaced.
  SyncState copyWith({
    bool? busy,
    Map<String, SyncResult>? results,
    String? error,
    DateTime? lastSyncAt,
  }) =>
      SyncState(
        busy: busy ?? this.busy,
        results: results ?? this.results,
        error: error,
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      );
}

/// Runs syncs and keeps their results. Used by the app bar and settings.
class SyncController extends StateNotifier<SyncState> {
  /// Creates a controller that uses [_ref] for the API client.
  SyncController(this._ref) : super(const SyncState());

  final Ref _ref;

  Dio get _dio => _ref.read(dioProvider);

  /// Syncs all connections (`POST /sync`).
  Future<void> syncAll() => _run(() async {
        final r = await _dio.post<Object?>('/sync');
        return _merge(r.data, replace: true);
      });

  /// Syncs one connection (`POST /connections/{id}/sync`).
  Future<void> retry(String connectionId) => _run(() async {
        final r = await _dio.post<Object?>('/connections/$connectionId/sync');
        final data = r.data;
        if (parseSyncResults(data).isEmpty && data is Map<String, dynamic>) {
          return _merge([data], replace: false);
        }
        return _merge(data, replace: false);
      });

  /// Loads the last known results (`GET /sync/status`).
  Future<void> loadStatus() => _run(() async {
        final r = await _dio.get<Object?>('/sync/status');
        return _merge(r.data, replace: true);
      });

  Future<void> _run(Future<SyncState> Function() action) async {
    if (state.busy) return;
    state = state.copyWith(busy: true);
    try {
      state = await action();
    } on DioException catch (e) {
      state = state.copyWith(busy: false, error: _describe(e));
    }
    _ref.invalidate(connectionsProvider);
  }

  String _describe(DioException e) {
    final code = e.response?.statusCode;
    if (code == null) {
      return 'Cannot reach the server. Nothing was lost. Try again later.';
    }
    return 'The server returned error $code. Try again later.';
  }

  SyncState _merge(Object? data, {required bool replace}) {
    final parsed = parseSyncResults(data);
    final map = replace ? <String, SyncResult>{} : {...state.results};
    for (final r in parsed) {
      map[r.connectionId] = r;
    }
    DateTime? at;
    if (data is Map && data['last_sync_at'] != null) {
      at = DateTime.tryParse('${data['last_sync_at']}');
    }
    return state.copyWith(
        busy: false, results: map, lastSyncAt: at ?? DateTime.now());
  }
}

/// Provides the sync controller.
final syncControllerProvider =
    StateNotifierProvider<SyncController, SyncState>(SyncController.new);

/// Provides the list of connections (`GET /connections`).
final connectionsProvider = FutureProvider<List<Connection>>((ref) async {
  final r = await ref.watch(dioProvider).get<Object?>('/connections');
  final data = r.data;
  if (data is! List) return const [];
  return [
    for (final item in data)
      if (item is Map<String, dynamic>) Connection.fromJson(item),
  ];
});
