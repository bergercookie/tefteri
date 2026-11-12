/// Monthly focus results, outside-focus milestones and earlier work.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/theme.dart';

/// Shows stored or live review results without recalculating the snapshot.
class ReviewResultsSection extends StatelessWidget {
  /// Creates the section from a snapshot payload.
  const ReviewResultsSection({required this.snapshot, super.key});

  /// Snapshot JSON from `GET /monthly/{month}/review`.
  final Map<String, dynamic> snapshot;

  @override
  Widget build(BuildContext context) {
    final themes = snapshot['themes'] as List? ?? const [];
    final outside = snapshot['outside_focus'] as List? ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Targets and results',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: Space.md),
        if (themes.isEmpty)
          EmptyState(
            message: 'No themes were saved for this month.',
            action: TextButton(
              onPressed: () =>
                  context.go('/month?date=${snapshot['month'] ?? ''}'),
              child: const Text('Return to monthly planning'),
            ),
          )
        else
          for (final raw in themes)
            if (raw is Map)
              _ReviewThemeCard(theme: Map<String, dynamic>.from(raw)),
        const SizedBox(height: Space.xl),
        Text('Outside focus', style: Theme.of(context).textTheme.titleMedium),
        Text(
          'Outside focus means a finished milestone whose theme was not in '
          'this month’s focus.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (outside.isEmpty)
          EmptyState(
            message: 'No milestones finished outside the focus.',
            action: TextButton(
              onPressed: () =>
                  context.go('/month?date=${snapshot['month'] ?? ''}'),
              child: const Text('Review the focus themes above'),
            ),
          )
        else
          for (final raw in outside)
            if (raw is Map) _OutsideRow(item: Map<String, dynamic>.from(raw)),
      ],
    );
  }
}

class _ReviewThemeCard extends StatelessWidget {
  const _ReviewThemeCard({required this.theme});

  final Map<String, dynamic> theme;

  @override
  Widget build(BuildContext context) {
    final name = '${theme['name'] ?? ''}';
    final target = theme['target'];
    final done = theme['done'] ?? 0;
    final marker = '${theme['marker'] ?? 'no_target'}';
    final milestoneRows = theme['milestones'] as List? ?? const [];
    final earlier = theme['earlier_not_counted'] as List? ?? const [];
    final orphaned = theme['orphaned'];
    final labelChanged = theme['label_changed'];
    return Container(
      key: Key('review-theme-${theme['project_id']}'),
      margin: const EdgeInsets.only(bottom: Space.md),
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        border: Border.all(color: context.tefteri.rule),
        borderRadius: BorderRadius.circular(Corner.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: Theme.of(context).textTheme.titleMedium),
          Text(
            target == null
                ? '$done milestones · no target'
                : '$done of $target',
            key: Key('review-result-${theme['project_id']}'),
          ),
          Text(_markerLabel(marker),
              key: Key('review-marker-${theme['project_id']}')),
          if (theme['status'] == 'swapped_out')
            const Text('Swapped out during the month'),
          if (orphaned is Map)
            Text(
              'No longer available: ${orphaned['reason'] ?? 'missing'}',
              key: Key('review-orphan-${theme['project_id']}'),
            ),
          if (labelChanged != null)
            Text('Label changed: $labelChanged',
                key: Key('review-label-changed-${theme['project_id']}')),
          if (milestoneRows.isEmpty)
            Text('No milestones counted.',
                style: Theme.of(context).textTheme.bodySmall),
          for (final raw in milestoneRows)
            if (raw is Map)
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: Text('${raw['done_on'] ?? ''} · ${raw['name'] ?? ''}'),
              ),
          if (earlier.isNotEmpty) ...[
            const SizedBox(height: Space.sm),
            Text(
                'Finished earlier in the month; not counted toward this target',
                style: Theme.of(context).textTheme.bodySmall),
            for (final raw in earlier)
              if (raw is Map)
                Text('${raw['done_on'] ?? ''} · ${raw['name'] ?? ''}'),
          ],
        ],
      ),
    );
  }

  String _markerLabel(String marker) => switch (marker) {
        'missed' => 'Missed',
        'met' => 'Met',
        'beaten' => 'Beaten',
        _ => 'No target',
      };
}

class _OutsideRow extends StatelessWidget {
  const _OutsideRow({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.xs),
        child: Row(
          children: [
            Expanded(child: Text('${item['name'] ?? ''}')),
            Text('Theme: ${item['theme_name'] ?? 'no theme'}',
                key: Key('outside-theme-${item['milestone_id']}')),
          ],
        ),
      );
}
