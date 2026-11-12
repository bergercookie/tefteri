/// One bar that shows how a period splits into the three work categories.
library;

import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import 'category_style.dart';
import 'statistics_models.dart';

/// The narrowest a segment may be, so that a small category stays visible.
const double minSegmentWidth = 8;

/// Space between two segments.
const double _gap = 2;

/// Height of the bar.
const double _barHeight = 28;

/// The width of each segment, left to right.
///
/// A segment is as wide as its [weights] say, but never narrower than
/// [minWidth]; the others give up the room. The widths and the gaps add up to
/// [available].
List<double> segmentWidths(List<num> weights, double available,
    {double minWidth = minSegmentWidth}) {
  final n = weights.length;
  if (n == 0) return const [];
  final room = available - _gap * (n - 1);
  final fixed = List<bool>.filled(n, false);
  var widths = List<double>.filled(n, 0);
  for (var round = 0; round <= n; round++) {
    final fixedTotal = [
      for (var i = 0; i < n; i++)
        if (fixed[i]) minWidth
    ].fold(0.0, (a, b) => a + b);
    final freeWeight = [
      for (var i = 0; i < n; i++)
        if (!fixed[i]) weights[i].toDouble(),
    ].fold(0.0, (a, b) => a + b);
    final freeCount = fixed.where((f) => !f).length;
    widths = [
      for (var i = 0; i < n; i++)
        if (fixed[i])
          minWidth
        else if (freeWeight > 0)
          (room - fixedTotal) * weights[i] / freeWeight
        else
          freeCount == 0 ? 0 : (room - fixedTotal) / freeCount,
    ];
    var changed = false;
    for (var i = 0; i < n; i++) {
      if (!fixed[i] && widths[i] < minWidth) {
        fixed[i] = true;
        changed = true;
      }
    }
    if (!changed) break;
  }
  return widths;
}

/// The bar, and under it the three names with their counts and shares.
///
/// The shares come from the server and are printed as they are. A category
/// with no task has no segment, but its name and a zero stay in the legend.
/// A period with no task draws nothing.
class ProportionBar extends StatelessWidget {
  /// Creates the bar.
  const ProportionBar({
    required this.counts,
    required this.percentages,
    this.onSelect,
    this.legend = true,
    super.key,
  });

  /// Tasks per category.
  final CategoryCounts counts;

  /// Whole percentages from the server.
  final CategoryCounts percentages;

  /// Called with the category of a tapped segment.
  final ValueChanged<Category>? onSelect;

  /// Whether to print the three names under the bar.
  final bool legend;

  @override
  Widget build(BuildContext context) {
    if (counts.isZero) return const SizedBox.shrink();
    final shown = [
      for (final c in Category.work)
        if (counts.of(c) > 0) c,
    ];
    final sumPercent =
        Category.work.fold<int>(0, (a, c) => a + percentages.of(c));
    num weight(Category c) => sumPercent > 0 ? percentages.of(c) : counts.of(c);
    final summary = 'Goal-aligned ${counts.goalAligned}, '
        'maintenance ${counts.maintenance}, '
        'off-plan ${counts.offPlan} tasks';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          explicitChildNodes: true,
          label: summary,
          child: LayoutBuilder(builder: (context, box) {
            final widths =
                segmentWidths([for (final c in shown) weight(c)], box.maxWidth);
            return SizedBox(
              key: const Key('proportion-bar'),
              height: _barHeight,
              child: Row(
                children: [
                  for (var i = 0; i < shown.length; i++) ...[
                    if (i > 0) const SizedBox(width: _gap),
                    _Segment(
                      category: shown[i],
                      width: widths[i],
                      count: counts.of(shown[i]),
                      percent: percentages.of(shown[i]),
                      onSelect: onSelect,
                    ),
                  ],
                ],
              ),
            );
          }),
        ),
        if (legend) ...[
          const SizedBox(height: Space.sm),
          ExcludeSemantics(
            child: Wrap(
              spacing: Space.lg,
              runSpacing: Space.xs,
              children: [
                for (final c in Category.work)
                  _LegendEntry(
                      category: c,
                      count: counts.of(c),
                      percent: percentages.of(c)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.category,
    required this.width,
    required this.count,
    required this.percent,
    required this.onSelect,
  });

  final Category category;
  final double width;
  final int count;
  final int percent;
  final ValueChanged<Category>? onSelect;

  @override
  Widget build(BuildContext context) {
    final style = categoryStyle(context, category);
    final tap = onSelect == null ? null : () => onSelect!(category);
    return Semantics(
      container: true,
      button: tap != null,
      label: '${style.semanticsLabel(count)}, $percent percent',
      onTap: tap,
      child: SizedBox(
        key: Key('bar-segment-${category.json}'),
        width: width,
        height: _barHeight,
        child: CategoryBlock(
          style: style,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: tap,
              excludeFromSemantics: true,
              child: width >= 28
                  ? Center(
                      child: Icon(style.icon, size: 16, color: style.iconColor))
                  : const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}

class _LegendEntry extends StatelessWidget {
  const _LegendEntry(
      {required this.category, required this.count, required this.percent});

  final Category category;
  final int count;
  final int percent;

  @override
  Widget build(BuildContext context) {
    final style = categoryStyle(context, category);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Row(
      key: Key('bar-legend-${category.json}'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(style.icon, size: 16, color: style.accent),
        const SizedBox(width: Space.xs),
        Text(style.name, style: text.bodyMedium),
        const SizedBox(width: Space.sm),
        Text('$count', style: text.labelLarge),
        const SizedBox(width: Space.xs),
        Text('$percent%',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
      ],
    );
  }
}
