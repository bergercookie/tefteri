/// Key results connected to a monthly focus theme and their planning flags.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/theme.dart';
import 'month_models.dart';

/// Shows year-to-date key result progress beside one focus theme.
class KeyResultStrip extends StatelessWidget {
  /// Creates the strip for [entry].
  const KeyResultStrip({
    required this.entry,
    required this.keyResults,
    super.key,
  });

  /// Theme entry whose linked results are shown.
  final MonthEntry entry;

  /// All key results returned by the planning endpoint.
  final List<Map<String, dynamic>> keyResults;

  @override
  Widget build(BuildContext context) {
    final relevant = keyResults
        .where((result) =>
            (result['theme_ids'] as List? ?? const [])
                .map((id) => '$id')
                .contains(entry.projectId) ||
            _hasFlag(result, 'no_usable_theme'))
        .toList();
    if (relevant.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: Space.sm),
        child: Text(
          'Not linked to a key result',
          key: Key('no-key-result-${entry.projectId}'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: Space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final result in relevant) _KeyResultRow(result: result),
        ],
      ),
    );
  }
}

bool _hasFlag(Map<String, dynamic> result, String code) =>
    (result['flags'] as List? ?? const [])
        .any((flag) => flag is Map && flag['code'] == code || flag == code);

class _KeyResultRow extends StatelessWidget {
  const _KeyResultRow({required this.result});

  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final current = result['current_value'];
    final at = result['current_at'];
    final target = result['target'];
    final deadline = result['deadline'];
    final flags = result['flags'] as List? ?? const [];
    final noUsable = flags.any((flag) =>
        flag is Map && flag['code'] == 'no_usable_theme' ||
        flag == 'no_usable_theme');
    final start = result['start_value'];
    return Container(
      margin: const EdgeInsets.only(bottom: Space.xs),
      padding: const EdgeInsets.all(Space.sm),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: context.tefteri.rule, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              '${result['goal_title'] ?? 'Key result'}: '
              '${result['metric'] ?? ''}',
              style: text.bodyMedium),
          Text('Start $start · Latest $current${at == null ? '' : ' · $at'}',
              style: text.bodySmall),
          Text('Target $target · Deadline $deadline', style: text.bodySmall),
          if (noUsable)
            Row(
              children: [
                Expanded(
                  child: Text(
                    'No usable theme. Link a theme in annual planning.',
                    key: Key('no-usable-theme-${result['id']}'),
                    style: text.bodySmall,
                  ),
                ),
                TextButton(
                  key: Key('annual-plan-${result['id']}'),
                  onPressed: () {
                    final year = result['deadline'] is String
                        ? '${result['deadline']}'.substring(0, 4)
                        : '${DateTime.now().year}';
                    context.go('/annual?year=$year');
                  },
                  child: const Text('Annual plan'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// One quiet line per annual goal whose key results have no theme in focus.
///
/// A goal is in focus when any of its key results serves a focus theme. The
/// lines are grouped by goal, so a goal with several key results is named once.
class GoalsWithoutFocus extends StatelessWidget {
  /// Creates the list for the focus themes [focusProjectIds].
  const GoalsWithoutFocus({
    required this.keyResults,
    required this.focusProjectIds,
    super.key,
  });

  /// All key results returned by the planning endpoint.
  final List<Map<String, dynamic>> keyResults;

  /// The project ids that are in this month's focus.
  final Set<String> focusProjectIds;

  @override
  Widget build(BuildContext context) {
    final inFocus = {
      for (final result in keyResults)
        if ((result['theme_ids'] as List? ?? const [])
            .map((id) => '$id')
            .any(focusProjectIds.contains))
          _goalKey(result),
    };
    final withoutFocus = <String, Map<String, dynamic>>{};
    for (final result in keyResults) {
      if (!_hasFlag(result, 'no_theme_in_focus') ||
          inFocus.contains(_goalKey(result))) {
        continue;
      }
      withoutFocus.putIfAbsent(_goalKey(result), () => result);
    }
    if (withoutFocus.isEmpty) return const SizedBox.shrink();
    final style = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Annual goals without a theme in focus',
              key: const Key('goals-without-focus'),
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: Space.xs),
          for (final result in withoutFocus.values)
            Text(
              'No theme in focus · ${result['goal_title'] ?? ''}',
              key: Key('no-theme-in-focus-${_goalKey(result)}'),
              style: style,
            ),
        ],
      ),
    );
  }
}

String _goalKey(Map<String, dynamic> result) =>
    '${result['goal_id'] ?? result['goal_title'] ?? result['id'] ?? ''}';
