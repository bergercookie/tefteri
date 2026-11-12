/// Monthly focus entries, targets, milestone progress and key-result links.
library;

import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import 'key_result_strip.dart';
import 'month_models.dart';
import 'target_field.dart';

/// Presents themes in the saved or editable focus.
class FocusSection extends StatelessWidget {
  /// Creates the focus section.
  const FocusSection({
    required this.entries,
    required this.keyResults,
    required this.onTargetChanged,
    this.onTargetValidityChanged,
    required this.onChooseThemes,
    this.readOnly = false,
    this.onSwap,
    this.onRemove,
    super.key,
  });

  /// Current focus entries.
  final List<Map<String, Object?>> entries;

  /// Key results returned by the planning endpoint.
  final List<Map<String, dynamic>> keyResults;

  /// Updates the unsaved target of one entry.
  final void Function(String projectId, int? target) onTargetChanged;

  /// Reports invalid visible text so Save cannot persist the previous value.
  final void Function(String projectId, bool valid)? onTargetValidityChanged;

  /// Opens the theme picker.
  final VoidCallback onChooseThemes;

  /// Swaps one active theme.
  final ValueChanged<Map<String, Object?>>? onSwap;

  /// Removes one active theme.
  final ValueChanged<Map<String, Object?>>? onRemove;

  /// Whether this past plan cannot be changed.
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (entries.isEmpty) {
      return EmptyState(
        key: const Key('empty-month-focus'),
        message: 'No themes are in this month’s focus yet.',
        action: OutlinedButton(
          key: const Key('choose-themes-empty'),
          onPressed: readOnly ? null : onChooseThemes,
          child: const Text('Choose themes'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Monthly focus', style: theme.textTheme.titleLarge),
        const SizedBox(height: Space.md),
        for (final entry in entries)
          _FocusEntryCard(
            entry: entry,
            keyResults: keyResults,
            onTargetChanged: onTargetChanged,
            onTargetValidityChanged: onTargetValidityChanged,
            onSwap: onSwap,
            onRemove: onRemove,
            readOnly: readOnly,
          ),
        if (!readOnly)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const Key('add-theme'),
              onPressed: onChooseThemes,
              icon: const Icon(Icons.add),
              label: const Text('Add a theme'),
            ),
          ),
      ],
    );
  }
}

class _FocusEntryCard extends StatelessWidget {
  const _FocusEntryCard({
    required this.entry,
    required this.keyResults,
    required this.onTargetChanged,
    required this.onTargetValidityChanged,
    required this.onSwap,
    required this.onRemove,
    required this.readOnly,
  });

  final Map<String, Object?> entry;
  final List<Map<String, dynamic>> keyResults;
  final void Function(String, int?) onTargetChanged;
  final void Function(String, bool)? onTargetValidityChanged;
  final ValueChanged<Map<String, Object?>>? onSwap;
  final ValueChanged<Map<String, Object?>>? onRemove;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final id = '${entry['project_id']}';
    final name = '${entry['name'] ?? ''}';
    final done = (entry['done'] as num? ?? 0).toInt();
    final target = entry['target'] as int?;
    final orphaned = entry['orphaned'];
    final labelChanged = entry['label_changed'];
    final progress = target == null || target == 0 ? null : done / target;
    return Container(
      key: Key('focus-entry-$id'),
      margin: const EdgeInsets.only(bottom: Space.md),
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: context.tefteri.rule),
        borderRadius: BorderRadius.circular(Corner.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child:
                    Text(name, style: Theme.of(context).textTheme.titleMedium),
              ),
              if (!readOnly && onSwap != null)
                TextButton(
                  key: Key('swap-theme-$id'),
                  onPressed: () => onSwap!(entry),
                  child: const Text('Swap'),
                ),
              if (!readOnly && onRemove != null)
                IconButton(
                  key: Key('remove-theme-$id'),
                  tooltip: 'Remove theme',
                  onPressed: () => onRemove!(entry),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
            ],
          ),
          if (orphaned is Map)
            Text(
              (orphaned['reason'] == 'archived')
                  ? 'Archived. This theme stays in the month’s history.'
                  : 'No longer in the task app. This theme stays in the month’s history.',
              key: Key('orphan-reason-$id'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (labelChanged != null)
            Text('Label changed to $labelChanged.',
                key: Key('label-changed-$id'),
                style: Theme.of(context).textTheme.bodySmall),
          Row(
            children: [
              Expanded(
                child: Text('$done milestones finished this month',
                    key: Key('focus-progress-$id')),
              ),
              SizedBox(
                width: 168,
                child: TargetField(
                  key: Key('target-$id'),
                  initialValue: target,
                  enabled: !readOnly && orphaned == null,
                  onChanged: (value) => onTargetChanged(id, value),
                  onValidityChanged: (valid) =>
                      onTargetValidityChanged?.call(id, valid),
                ),
              ),
            ],
          ),
          if (progress != null)
            LinearProgressIndicator(
              key: Key('focus-target-progress-$id'),
              value: progress.clamp(0.0, 1.0).toDouble(),
              minHeight: Space.xs,
            ),
          KeyResultStrip(
            entry: MonthEntry.fromJson({
              'id': entry['id'],
              'project_id': id,
              'connection_id': entry['connection_id'],
              'name': name,
              'target': target,
              'counts_from': entry['counts_from'],
              'left_on': entry['left_on'],
              'status': entry['status'],
              'done': done,
              'earlier_not_counted': entry['earlier_not_counted'],
              'marker': entry['marker'],
              'orphaned': entry['orphaned'],
              'label_changed': labelChanged,
              'linked_key_results': entry['linked_key_results'],
              'last_month_done': entry['last_month_done'],
            }),
            keyResults: keyResults,
          ),
        ],
      ),
    );
  }
}
