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
    this.onOpenPicker,
    super.key,
  });

  /// Theme entry whose linked results are shown.
  final MonthEntry entry;

  /// All key results returned by the planning endpoint.
  final List<Map<String, dynamic>> keyResults;

  /// Optional action for the quiet no-theme-in-focus flag.
  final VoidCallback? onOpenPicker;

  @override
  Widget build(BuildContext context) {
    final relevant = keyResults
        .where((result) =>
            (result['theme_ids'] as List? ?? const [])
                .map((id) => '$id')
                .contains(entry.projectId) ||
            _hasFlag(result, 'no_usable_theme'))
        .toList();
    final relevantIds = relevant
        .map((result) => result['id'] ?? result['key_result_id'])
        .toSet();
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
          for (final result in keyResults.where((result) =>
              _hasFlag(result, 'no_theme_in_focus') &&
              !(result['theme_ids'] as List? ?? const [])
                  .map((id) => '$id')
                  .contains(entry.projectId) &&
              !relevantIds.contains(result['id'] ?? result['key_result_id'])))
            _NoFocusFlag(
              result: result,
              onOpenPicker: onOpenPicker,
            ),
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
    final scheme = Theme.of(context).colorScheme;
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
          for (final flag in flags)
            if (flag is Map && flag['code'] == 'no_theme_in_focus')
              Text(
                'No theme in focus',
                key: Key('no-theme-in-focus-${result['id']}'),
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
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

class _NoFocusFlag extends StatelessWidget {
  const _NoFocusFlag({required this.result, this.onOpenPicker});

  final Map<String, dynamic> result;
  final VoidCallback? onOpenPicker;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          key: Key('no-theme-in-focus-${result['id']}'),
          onPressed: onOpenPicker,
          child: Text('No theme in focus · ${result['goal_title'] ?? ''}'),
        ),
      );
}
