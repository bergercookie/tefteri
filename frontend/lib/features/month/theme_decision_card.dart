/// End-of-month carry, drop, replace and decide-later choices.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/theme.dart';
import 'month_api.dart';
import 'month_models.dart';

/// One review decision and its effect-first confirmation.
class ThemeDecisionCard extends ConsumerStatefulWidget {
  /// Creates a decision card for one snapshot theme.
  const ThemeDecisionCard({
    required this.month,
    required this.theme,
    required this.initialDecision,
    required this.onChanged,
    super.key,
  });

  /// Month key for available replacements.
  final String month;

  /// Theme payload from the review.
  final Map<String, dynamic> theme;

  /// Previously stored choice, or `later`.
  final String initialDecision;

  /// Called after the choice is confirmed.
  final void Function(String decision, {String? replacementProjectId})
      onChanged;

  @override
  ConsumerState<ThemeDecisionCard> createState() => _ThemeDecisionCardState();
}

class _ThemeDecisionCardState extends ConsumerState<ThemeDecisionCard> {
  late String _decision;
  String? _replacementName;

  @override
  void initState() {
    super.initState();
    _decision = widget.initialDecision;
  }

  @override
  void didUpdateWidget(covariant ThemeDecisionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialDecision != widget.initialDecision) {
      _decision = widget.initialDecision;
      _replacementName = null;
    }
  }

  Future<void> _choose(String choice) async {
    String? replacementId;
    String? replacementName;
    if (choice == 'replace') {
      final picker = await ref.read(monthApiProvider).themes(widget.month);
      if (!mounted) return;
      final options = picker.themes
          .where((item) => item.projectId != widget.theme['project_id']);
      if (options.isEmpty) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('No replacement theme available'),
            content: const EmptyState(
              message: 'Choose a live theme in monthly planning first.',
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close')),
            ],
          ),
        );
        return;
      }
      final picked = await showDialog<MonthTheme>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Choose a replacement theme'),
          content: SizedBox(
            width: 440,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final option in options)
                  ListTile(
                    key: Key('replace-theme-${option.projectId}'),
                    title: Text(option.name),
                    subtitle: Text(option.connectionName),
                    onTap: () => Navigator.pop(context, option),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
          ],
        ),
      );
      if (!mounted || picked == null) return;
      replacementId = picked.projectId;
      replacementName = picked.name;
    }

    final theme = widget.theme;
    final effect = switch (choice) {
      'carry' => '${theme['name']} will be offered next month with '
          '${theme['target'] == null ? 'no target' : 'target ${theme['target']}'}.',
      'drop' => '${theme['name']} will not be suggested next month.',
      'replace' =>
        '$replacementName will be suggested next month instead of ${theme['name']}.',
      _ => 'You can decide what to do with ${theme['name']} later.',
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirm ${choice == 'later' ? 'decide later' : choice}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(effect, key: const Key('decision-effect')),
            if (choice == 'replace') ...[
              const SizedBox(height: Space.sm),
              Text(
                'Replace is a month-end decision. Swap changes the focus '
                'during the month.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-theme-decision'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Keep this choice'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _decision = choice;
      _replacementName = replacementName;
    });
    widget.onChanged(choice, replacementProjectId: replacementId);
  }

  @override
  Widget build(BuildContext context) => Container(
        key: Key('decision-card-${widget.theme['project_id']}'),
        margin: const EdgeInsets.only(top: Space.md),
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(
          border: Border.all(color: context.tefteri.rule),
          borderRadius: BorderRadius.circular(Corner.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${widget.theme['name'] ?? ''}',
                style: Theme.of(context).textTheme.titleSmall),
            if (_decision != 'later')
              Text(
                _decision == 'replace'
                    ? 'Replace with ${_replacementName ?? 'another theme'}'
                    : 'Decision: $_decision',
                key: Key('decision-current-${widget.theme['project_id']}'),
              ),
            Wrap(
              spacing: Space.xs,
              children: [
                for (final choice in ['carry', 'drop', 'replace', 'later'])
                  TextButton(
                    key: Key('decision-${widget.theme['project_id']}-$choice'),
                    onPressed: () => _choose(choice),
                    child: Text(choice == 'later' ? 'Decide later' : choice),
                  ),
              ],
            ),
            if (_decision != 'later')
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: Key('undo-decision-${widget.theme['project_id']}'),
                  onPressed: () {
                    setState(() {
                      _decision = 'later';
                      _replacementName = null;
                    });
                    widget.onChanged('later');
                  },
                  child: const Text('Undo decision'),
                ),
              ),
          ],
        ),
      );
}
