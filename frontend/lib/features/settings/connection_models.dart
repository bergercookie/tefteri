/// Data models for connections and sync results.
library;

import 'package:flutter/foundation.dart';

/// Why a connection failed to sync.
enum FailureReason {
  /// The service did not answer.
  unreachable,

  /// The credentials expired or were revoked.
  authExpired,

  /// Any other failure.
  other;

  /// Parses the API value; unknown values map to [other].
  static FailureReason parse(Object? value) => switch (value) {
        'unreachable' => FailureReason.unreachable,
        'auth_expired' => FailureReason.authExpired,
        _ => FailureReason.other,
      };

  /// Short plain-English explanation for the user.
  String get message => switch (this) {
        FailureReason.unreachable => 'The service is not reachable.',
        FailureReason.authExpired =>
          'Your credentials expired or were revoked.',
        FailureReason.other => 'The sync failed.',
      };
}

/// A configured connection to an external service.
@immutable
class Connection {
  /// Creates a connection.
  const Connection({
    required this.id,
    required this.kind,
    required this.provider,
    required this.displayName,
    required this.status,
    this.settings = const {},
    this.lastSyncAt,
    this.lastSyncOutcome,
  });

  /// Parses one item of `GET /connections`.
  factory Connection.fromJson(Map<String, dynamic> json) => Connection(
        id: '${json['id']}',
        kind: '${json['kind'] ?? ''}',
        provider: '${json['provider'] ?? ''}',
        displayName: '${json['display_name'] ?? ''}',
        settings: json['settings'] is Map<String, dynamic>
            ? json['settings'] as Map<String, dynamic>
            : const {},
        status: '${json['status'] ?? 'ok'}',
        lastSyncAt: json['last_sync_at'] == null
            ? null
            : DateTime.tryParse('${json['last_sync_at']}'),
        lastSyncOutcome: json['last_sync_outcome'] as String?,
      );

  /// Connection id.
  final String id;

  /// Kind of data (for example calendar or tasks).
  final String kind;

  /// Provider name (for example google).
  final String provider;

  /// Name shown to the user.
  final String displayName;

  /// Provider settings, for example `base_url`. Never holds credentials.
  final Map<String, dynamic> settings;

  /// Status: `ok`, `needs_attention` or `error`.
  final String status;

  /// Time of the last sync, if any.
  final DateTime? lastSyncAt;

  /// Outcome of the last sync, if any.
  final String? lastSyncOutcome;

  /// True when the connection needs the user to act.
  bool get isFailing =>
      status != 'ok' || (lastSyncOutcome != null && lastSyncOutcome != 'ok');
}

/// Result of a sync for one connection.
@immutable
class SyncResult {
  /// Creates a result.
  const SyncResult({
    required this.connectionId,
    required this.name,
    required this.outcome,
    this.reason,
    this.detail,
    this.counts = const {},
  });

  /// Parses one per-connection result.
  factory SyncResult.fromJson(Map<String, dynamic> json) {
    final counts = <String, int>{};
    final raw = json['counts'];
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v is num) counts['$k'] = v.toInt();
      });
    }
    return SyncResult(
      connectionId: '${json['connection_id']}',
      name: '${json['name'] ?? ''}',
      outcome: '${json['outcome'] ?? 'ok'}',
      reason:
          json['reason'] == null ? null : FailureReason.parse(json['reason']),
      detail: json['detail'] as String?,
      counts: counts,
    );
  }

  /// Connection id.
  final String connectionId;

  /// Connection name.
  final String name;

  /// `ok`, `needs_attention` or `error`.
  final String outcome;

  /// Failure reason; null when the sync succeeded.
  final FailureReason? reason;

  /// The underlying error from the server, for example the address that
  /// could not be reached.
  final String? detail;

  /// Item counts by name.
  final Map<String, int> counts;

  /// True when the sync failed.
  bool get failed => outcome != 'ok';

  /// The reason to show; derives one from [outcome] when the API gave none.
  FailureReason get effectiveReason =>
      reason ??
      (outcome == 'needs_attention'
          ? FailureReason.authExpired
          : FailureReason.other);
}

/// Parses a sync response: a list, or an object with `results`
/// (or `connections`) and an optional `last_sync_at`.
List<SyncResult> parseSyncResults(Object? data) {
  Object? list = data;
  if (data is Map) list = data['results'] ?? data['connections'];
  if (list is! List) return const [];
  return [
    for (final item in list)
      if (item is Map<String, dynamic>) SyncResult.fromJson(item),
  ];
}
