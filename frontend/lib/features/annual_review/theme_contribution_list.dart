/// The themes that served one key result, with their milestones and hints.
library;

import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import 'annual_review_models.dart';

/// Lists the themes of a key result. More than twenty fold into a group.
class ThemeContributionList extends StatelessWidget {
  /// Creates the list.
  const ThemeContributionList(
      {required this.themes, super.key, this.initiallyOpen = false});

  /// The linked themes.
  final List<ThemeContribution> themes;

  /// Whether the list starts open when it is long.
  final bool initiallyOpen;

  @override
  Widget build(BuildContext context) {
    if (themes.isEmpty) return const SizedBox.shrink();
    if (themes.length > 20 && !initiallyOpen) {
      return _Collapsible(themes: themes);
    }
    return Column(
      key: const Key('theme-list'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final t in themes) _ThemeRow(theme: t)],
    );
  }
}

class _Collapsible extends StatefulWidget {
  const _Collapsible({required this.themes});

  final List<ThemeContribution> themes;

  @override
  State<_Collapsible> createState() => _CollapsibleState();
}

class _CollapsibleState extends State<_Collapsible> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextButton.icon(
          key: const Key('themes-toggle'),
          onPressed: () => setState(() => _open = !_open),
          icon: Icon(_open ? Icons.expand_less : Icons.expand_more),
          label: Text(_open
              ? 'Hide the ${widget.themes.length} themes'
              : 'Show the ${widget.themes.length} themes'),
        ),
        if (_open)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (final t in widget.themes) _ThemeRow(theme: t)],
          ),
      ],
    );
  }
}

class _ThemeRow extends StatelessWidget {
  const _ThemeRow({required this.theme});

  final ThemeContribution theme;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final quiet = text.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final ranges = theme.ranges
        .map((r) => '${_day(r.from)} to ${r.to == null ? 'now' : _day(r.to)}')
        .join(', ');
    final hint = switch (theme.hint) {
      'much_shipped_little_movement' =>
        '${theme.shipped} milestones shipped and the key result moved '
            '${_percent(theme.movement?.fraction)}. The theme target was '
            '${theme.targetSum ?? 0}.',
      'movement_not_from_theme' =>
        'No milestone shipped and the key result moved '
            '${_percent(theme.movement?.fraction)}.',
      _ => null,
    };
    return Container(
      key: Key('theme-${theme.projectId ?? theme.name}'),
      margin: const EdgeInsets.only(top: Space.xs),
      padding: const EdgeInsets.all(Space.sm),
      decoration: BoxDecoration(
        border: Border.all(color: context.tefteri.rule),
        borderRadius: BorderRadius.circular(Corner.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(theme.name, style: text.titleSmall)),
              if (theme.orphaned != null)
                Text('No longer in the task app (${theme.orphaned})',
                    key: const Key('theme-orphaned'), style: quiet),
              if (theme.label != null && theme.label != 'theme')
                Text('now labelled ${theme.label}', style: quiet),
            ],
          ),
          Text(
              '${theme.shipped} shipped, ${theme.shippedOutsideFocus} outside '
              'the focus. Target ${theme.targetSum ?? 'not stored'}.',
              style: quiet),
          if (theme.movement != null)
            Text(
                'Movement ${_number(theme.movement!.from)} to '
                '${_number(theme.movement!.to)} '
                '(${_percent(theme.movement!.fraction)}).',
                style: quiet),
          if (ranges.isNotEmpty) Text('Active $ranges.', style: quiet),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text(hint,
                  key: const Key('theme-hint'), style: text.bodySmall),
            ),
        ],
      ),
    );
  }
}

String _day(DateTime? d) => d == null
    ? ''
    : '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';

String _number(double v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';

String _percent(double? fraction) =>
    fraction == null ? 'not known' : '${(fraction * 100).round()}%';
