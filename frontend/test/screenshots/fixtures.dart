/// Fake data for the documentation screenshots. Names and items are
/// invented; there are no real credentials or personal data.
library;

import 'screenshot_helper.dart';

/// A calendar entry JSON object.
Map<String, Object?> entryJson(String id, String title, DateTime start,
        {DateTime? end, String? location}) =>
    {
      'id': id,
      'connection_id': 'c2',
      'title': title,
      'start': start.toUtc().toIso8601String(),
      'end': (end ?? start.add(const Duration(minutes: 30)))
          .toUtc()
          .toIso8601String(),
      'all_day': false,
      'location': location,
      'sync_state': 'synced',
    };

/// A note JSON object.
Map<String, Object?> noteJson(String id, String title,
        {String kind = 'custom', String body = '', List<String>? taskIds}) =>
    {
      'id': id,
      'connection_id': 'c3',
      'kind': kind,
      'title': title,
      'body': body,
      'note_date': null,
      'sync_state': 'synced',
      if (taskIds != null) 'task_ids': taskIds,
    };

/// The three example connections.
final connections = [
  {
    ...connectionJson('c1', 'tasks', 'Home tasks'),
    'provider': 'vikunja',
    'last_sync_at': '2026-11-02T08:15:00Z',
    'last_sync_outcome': 'ok',
  },
  {
    ...connectionJson('c2', 'calendar', 'Work calendar'),
    'provider': 'google_calendar',
    'last_sync_at': '2026-11-02T08:15:00Z',
    'last_sync_outcome': 'ok',
  },
  {
    ...connectionJson('c3', 'notes', 'Notes'),
    'provider': 'trilium',
    'last_sync_at': '2026-11-02T08:15:00Z',
    'last_sync_outcome': 'ok',
  },
];

/// The example day, Monday 2 November 2026.
final day = DateTime(2026, 11, 2);

/// The day view of [day].
Map<String, Object?> dayView() => {
      'date': '2026-11-02',
      'entries': [
        entryJson('e1', 'Team standup', DateTime(2026, 11, 2, 9),
            location: 'Room 4'),
        entryJson('e2', 'Dentist', DateTime(2026, 11, 2, 16),
            end: DateTime(2026, 11, 2, 17)),
      ],
      'tasks': [
        taskJson('t1', 'Write the release notes'),
        taskJson('t2', 'Buy a birthday present'),
        taskJson('t3', 'Review the test plan', status: 'done'),
      ],
      'note': noteJson('n0', '2026-11-02',
          kind: 'daily',
          body: 'Focus: release notes first.\n- Ask the team about the beta.'),
    };
