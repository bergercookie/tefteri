/// The calendars that a new event can go into.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

/// A calendar that a new event can go into: it is on, and the user can change
/// what it holds.
class EventCalendar {
  /// Creates a calendar.
  const EventCalendar({
    required this.connectionId,
    required this.connectionName,
    required this.containerId,
    required this.name,
    this.color,
  });

  /// Id of the connection that holds the calendar.
  final String connectionId;

  /// Name of that connection (a Google account).
  final String connectionName;

  /// Id of the calendar in tefteri.
  final String containerId;

  /// Name of the calendar.
  final String name;

  /// Its color in the calendar app (`#rrggbb`), or null.
  final String? color;
}

/// Every calendar of every calendar connection that is on and not read-only.
final eventCalendarsProvider = FutureProvider<List<EventCalendar>>((ref) async {
  final dio = ref.watch(dioProvider);
  Future<List<Map<String, dynamic>>> list(String path) async {
    final r = await dio.get<Object?>(path);
    return [
      for (final e in (r.data as List? ?? const []))
        if (e is Map<String, dynamic>) e,
    ];
  }

  final out = <EventCalendar>[];
  for (final c in await list('/connections')) {
    if (c['kind'] != 'calendar') continue;
    final id = '${c['id']}';
    for (final p in await list('/connections/$id/containers')) {
      if (p['enabled'] == false || p['read_only'] == true) continue;
      out.add(EventCalendar(
        connectionId: id,
        connectionName: '${c['display_name']}',
        containerId: '${p['id']}',
        name: '${p['name']}',
        color: p['color'] as String?,
      ));
    }
  }
  out.sort((a, b) {
    final byConnection = a.connectionName.compareTo(b.connectionName);
    return byConnection != 0
        ? byConnection
        : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return out;
});

/// The calendar of the last new event. The next one starts there.
final lastEventCalendarProvider = StateProvider<String?>((_) => null);
