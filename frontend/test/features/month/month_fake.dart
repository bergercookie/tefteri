import 'dart:convert';

import 'package:dio/dio.dart';
import '../../support/fake_api.dart';

/// Stateful fake monthly server for focus, change history and review flows.
class MonthFakeApi extends FakeApi {
  MonthFakeApi({
    this.month = '2030-03',
    Map<String, Object?>? plan,
    Map<String, Object?>? picker,
    Map<String, Object?>? suggestions,
    Map<String, Object?>? review,
    this.legacyGoals = const [],
  })  : plan = plan ??
            monthlyJson(
              month: month,
              entries: [
                monthlyEntryJson('e1', 'p1', 'Open source',
                    target: 3, done: 2, marker: 'missed', lastMonthDone: 2),
              ],
              keyResults: [
                monthlyKeyResultJson(themeIds: const ['p1']),
              ],
            ),
        picker = picker ??
            monthlyPickerJson(themes: [
              monthlyThemeJson('p1', 'Open source', inFocus: true),
              monthlyThemeJson('p2', 'Admin tools'),
              monthlyThemeJson('p3', 'Research'),
            ]),
        suggestions = suggestions ??
            monthlySuggestionsJson(
              fromMonth: '2030-02',
              suggestions: [
                monthlySuggestionJson('p1', 'Open source', target: 3),
              ],
            ),
        review = review ??
            monthlyReviewJson(
              month: month,
              snapshot: monthlySnapshotJson(
                themes: [
                  monthlyReviewThemeJson(
                    projectId: 'p1',
                    name: 'Open source',
                    milestones: [
                      {
                        'milestone_id': 'm1',
                        'name': 'Ship login',
                        'done_on': '$month-12',
                      },
                    ],
                  ),
                ],
                keyResults: [
                  monthlyReviewKeyResultJson(themeIds: const ['p1']),
                ],
              ),
            ),
        super({}) {
    routes.addAll(allRoutes());
    _version = ((this.review['current_version'] as num?) ??
            (this.review['version'] as num?) ??
            0)
        .toInt();
  }

  final String month;
  final List<Map<String, Object?>> legacyGoals;
  final Map<String, Object?> plan;
  final Map<String, Object?> picker;
  final Map<String, Object?> suggestions;
  final Map<String, Object?> review;
  final List<Map<String, Object?>> historyRows = [];
  final Map<String, Map<String, Object?>> _beforeChange = {};
  int _batch = 0;
  int _version = 0;

  /// Complete route table for one month.
  Map<String, Object?> allRoutes() => {
        'GET /monthly/$month': (_) => _copy(plan),
        'GET /monthly/$month/themes': (_) => _copy(picker),
        'GET /monthly/$month/suggestions': (_) => _copy(suggestions),
        'PUT /monthly/$month/focus': _saveFocus,
        'POST /monthly/$month/changes': _change,
        'POST /monthly/$month/changes/undo': _undo,
        'GET /monthly/$month/history': (_) => {
              'month': month,
              'changes': _forJson(historyRows),
            },
        'GET /monthly/$month/review': (_) => _copy(review),
        'POST /monthly/$month/review': _saveReview,
        'POST /monthly/$month/review/current': _makeCurrent,
        'GET /goals/history': (_) => _forJson(legacyGoals),
        'GET /checklists/month/$month-01': (_) => {
              'period_type': 'month',
              'period_start': '$month-01',
              'items': const [],
              'done': 0,
              'total': 0,
            },
        'GET /projects/classification': (_) => {
              'unsorted_count': 1,
              'connections': [
                {
                  'connection_id': 'c1',
                  'name': 'Work',
                  'projects': [
                    classifiedJson('u1', 'Unsorted project'),
                  ],
                },
              ],
            },
        'PUT /projects/labels': (_) => {
              'batch_id': 'label-batch',
              'effect': {'changed': 1, 'by_change': [], 'in_committed_plan': 0},
            },
        'POST /annual/themes': (_) => {'id': 'created-theme'},
      };

  Object? _saveFocus(RequestOptions options) {
    final body = _body(options);
    final entries = body['entries'] as List? ?? const [];
    final note = switch (entries.length) {
      0 => 'empty',
      1 || 2 => 'below',
      > 5 => 'above',
      _ => null,
    };
    if (body['dry_run'] == true) {
      return {
        'effect': {
          'added': entries,
          'removed': const [],
          'targets_changed': const [],
          'counts_from': '$month-01',
          'finished_earlier_in_month': 0,
          'finished_earlier': const [],
          'weekly_commitments_unchanged': 0,
          'out_keeps_results': false,
          'message': 'The focus will be saved for $month.',
        },
        'count_note': note,
      };
    }
    final themes = picker['themes'] as List? ?? const [];
    plan['entries'] = [
      for (final item in entries)
        if (item is Map) _entryFor(item, themes),
    ];
    plan['focus_known'] = true;
    plan['count_note'] = note;
    return {'focus': _copy(plan), 'count_note': note};
  }

  Object? _change(RequestOptions options) {
    final body = _body(options);
    final kind = '${body['kind']}';
    final outId = body['out_project_id'] as String?;
    final inId = body['in_project_id'] as String?;
    final effect = {
      'counts_from': '2030-03-14',
      'finished_earlier_in_month': 1,
      'finished_earlier': [
        {
          'milestone_id': 'm-before',
          'name': 'Finished earlier',
          'done_on': '2030-03-02'
        },
      ],
      'weekly_commitments_unchanged': 2,
      'out_keeps_results': outId != null,
      'message':
          'The change takes effect today. Weekly commitments stay as they are.',
    };
    if (body['dry_run'] == true) return {'effect': effect};

    final before = _copy(plan);
    final rows = (plan['entries'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, Object?>.from(item))
        .toList();
    final outIndex = outId == null
        ? -1
        : rows.indexWhere((item) => item['project_id'] == outId);
    final out = outIndex < 0 ? null : rows[outIndex];
    if (kind == 'remove' || kind == 'swap') {
      if (out != null) {
        rows[outIndex] = {
          ...out,
          'status': 'swapped_out',
          'left_on': '2030-03-14'
        };
        for (final item in picker['themes'] as List? ?? const []) {
          if (item is Map && item['project_id'] == outId) {
            item['left_this_month'] = true;
            item['in_focus'] = false;
          }
        }
      }
    } else if (kind == 'target' && outIndex >= 0) {
      rows[outIndex] = {...rows[outIndex], 'target': body['target']};
    }
    if ((kind == 'add' || kind == 'swap') && inId != null) {
      final theme = (picker['themes'] as List? ?? const [])
          .whereType<Map>()
          .firstWhere((item) => item['project_id'] == inId,
              orElse: () => {'project_id': inId, 'name': 'New theme'});
      rows.add({
        ...monthlyEntryJson(
          'entry-$inId',
          inId,
          '${theme['name']}',
          target: body['target'] as int?,
          countsFrom: '2030-03-14',
        ),
      });
    }
    plan['entries'] = rows;
    plan['focus_known'] = true;
    final batch = 'batch-${++_batch}';
    _beforeChange[batch] = before;
    historyRows.add({
      'batch_id': batch,
      'kind': kind,
      'on': '2030-03-14',
      'out_name': out?['name'],
      'in_name': inId == null ? null : 'New theme',
      'target_before': out?['target'],
      'target_after': body['target'],
      'source': 'user',
      'undone': false,
      'can_undo': true,
    });
    return {'batch_id': batch, 'effect': effect, 'focus': _copy(plan)};
  }

  Object? _undo(RequestOptions options) {
    final batch = '${_body(options)['batch_id']}';
    final previous = _beforeChange.remove(batch);
    if (previous != null) {
      plan
        ..clear()
        ..addAll(_copy(previous));
      final focused = (plan['entries'] as List? ?? const [])
          .whereType<Map>()
          .where((item) => item['status'] == 'in_focus')
          .map((item) => item['project_id'])
          .toSet();
      for (final item in picker['themes'] as List? ?? const []) {
        if (item is Map) {
          item['in_focus'] = focused.contains(item['project_id']);
          item['left_this_month'] = false;
        }
      }
      for (final row in historyRows) {
        if (row['batch_id'] == batch) {
          row['undone'] = true;
          row['can_undo'] = false;
        }
      }
    }
    return {'undone': 'swap', 'focus': _copy(plan)};
  }

  Object? _saveReview(RequestOptions options) {
    final body = _body(options);
    final snapshot = _copy(review['snapshot']);
    if (body['dry_run'] == true) {
      return {
        'snapshot': snapshot,
        'effects': const [],
        'will_create_version': _version + 1,
      };
    }
    _version++;
    review
      ..['stored'] = true
      ..['draft'] = false
      ..['version'] = _version
      ..['current_version'] = _version
      ..['taken_at'] = '2030-04-02T08:00:00Z';
    review['snapshot'] = snapshot;
    review['versions'] = [
      for (var i = 1; i <= _version; i++)
        {
          'version': i,
          'taken_at': '2030-04-02T08:00:00Z',
          'current': i == _version,
        },
    ];
    return {
      'version': _version,
      'snapshot': snapshot,
      'values_written': const [],
    };
  }

  Object? _makeCurrent(RequestOptions options) {
    final body = _body(options);
    final version = (body['version'] as num).toInt();
    if (body['dry_run'] == true) {
      return {
        'message': 'Version $version becomes the current version. '
            'Version $_version stays in the history.',
      };
    }
    review['current_version'] = version;
    return _copy(review);
  }

  Map<String, Object?> _entryFor(Object? raw, List<Object?> themes) {
    final item =
        raw is Map ? Map<String, Object?>.from(raw) : <String, Object?>{};
    final theme = themes.whereType<Map>().firstWhere(
        (candidate) => candidate['project_id'] == item['project_id'],
        orElse: () => const {});
    return monthlyEntryJson(
      'entry-${item['project_id']}',
      '${item['project_id']}',
      '${theme['name'] ?? 'Theme'}',
      connectionId: '${theme['connection_id'] ?? 'c1'}',
      target: item['target'] as int?,
    );
  }

  Map<String, dynamic> _body(RequestOptions options) =>
      options.data is Map ? Map<String, dynamic>.from(options.data as Map) : {};

  Map<String, Object?> _copy(Object? value) =>
      Map<String, Object?>.from(jsonDecode(jsonEncode(value)) as Map);

  Object? _forJson(Object? value) => jsonDecode(jsonEncode(value));
}
