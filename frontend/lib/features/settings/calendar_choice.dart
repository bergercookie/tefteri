/// Which calendars of a connection tefteri syncs: model, API and providers.
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';

/// One calendar of a connection (a "container" on the server).
@immutable
class CalendarInfo {
  /// Creates a calendar.
  const CalendarInfo({
    required this.id,
    required this.name,
    this.color,
    this.enabled = false,
    this.readOnly = false,
  });

  /// Parses one item of `GET /connections/{id}/containers`.
  factory CalendarInfo.fromJson(Map<String, dynamic> json) => CalendarInfo(
        id: '${json['id']}',
        name: '${json['name'] ?? ''}',
        color: json['color'] as String?,
        enabled: json['enabled'] == true,
        readOnly: json['read_only'] == true,
      );

  /// Container id.
  final String id;

  /// Name shown to the user.
  final String name;

  /// Color as `#rrggbb`, or null.
  final String? color;

  /// Whether tefteri syncs this calendar.
  final bool enabled;

  /// Whether the user cannot change events of this calendar.
  final bool readOnly;
}

/// What the server answered to saving the choice.
@immutable
class CalendarSaveResult {
  /// Creates a result.
  const CalendarSaveResult({
    required this.calendars,
    this.syncOutcome,
    this.syncReason,
    this.syncDetail,
  });

  /// The calendars after the change.
  final List<CalendarInfo> calendars;

  /// Outcome of the sync that followed (`ok` when it worked).
  final String? syncOutcome;

  /// Reason code of a failed sync.
  final Object? syncReason;

  /// Detail text of a failed sync.
  final String? syncDetail;

  /// Whether the sync failed.
  bool get syncFailed => syncOutcome != null && syncOutcome != 'ok';
}

List<CalendarInfo> _parseList(Object? data) => [
      if (data is List)
        for (final item in data)
          if (item is Map<String, dynamic>) CalendarInfo.fromJson(item),
    ];

/// Calls the container endpoints.
class CalendarChoiceApi {
  /// Creates the wrapper.
  const CalendarChoiceApi(this._dio);

  final Dio _dio;

  /// `GET /connections/{id}/containers`.
  Future<List<CalendarInfo>> list(String connectionId) async {
    final r = await _dio.get<Object?>('/connections/$connectionId/containers');
    return _parseList(r.data);
  }

  /// `PUT /connections/{id}/containers/enabled`: switches on exactly [ids].
  Future<CalendarSaveResult> save(String connectionId, List<String> ids) async {
    final r = await _dio.put<Map<String, dynamic>>(
      '/connections/$connectionId/containers/enabled',
      data: {'container_ids': ids},
    );
    final data = r.data ?? const <String, dynamic>{};
    final sync = data['sync'];
    return CalendarSaveResult(
      calendars: _parseList(data['containers']),
      syncOutcome: sync is Map ? sync['outcome'] as String? : null,
      syncReason: sync is Map ? sync['reason'] : null,
      syncDetail: sync is Map ? sync['detail'] as String? : null,
    );
  }
}

/// Provides the API wrapper.
final calendarChoiceApiProvider = Provider<CalendarChoiceApi>(
    (ref) => CalendarChoiceApi(ref.watch(dioProvider)));

/// The calendars of one connection.
final calendarsProvider = FutureProvider.autoDispose
    .family<List<CalendarInfo>, String>((ref, connectionId) =>
        ref.watch(calendarChoiceApiProvider).list(connectionId));

/// How many calendars of a connection are on, and how many exist.
/// Null when the server cannot tell.
final calendarCountProvider = FutureProvider.autoDispose
    .family<({int on, int total})?, String>((ref, connectionId) async {
  try {
    final list = await ref.watch(calendarChoiceApiProvider).list(connectionId);
    return (on: list.where((c) => c.enabled).length, total: list.length);
  } on DioException {
    return null;
  }
});
