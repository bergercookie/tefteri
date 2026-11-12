/// The three counts of a period side by side, each with its share.
library;

import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import 'category_style.dart';
import 'statistics_models.dart';

/// Three tiles, one per work category, always all three. Each shows the plain
/// count and the share next to it, and opens the tasks behind it.
class CategoryCountsRow extends StatelessWidget {
  /// Creates the row.
  const CategoryCountsRow(
      {required this.counts,
      required this.percentages,
      this.onSelect,
      super.key});

  /// Tasks per category.
  final CategoryCounts counts;

  /// Whole percentages from the server.
  final CategoryCounts percentages;

  /// Called with the category of a tapped tile.
  final ValueChanged<Category>? onSelect;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
          child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < Category.work.length; i++) ...[
            if (i > 0) const SizedBox(width: Space.sm),
            Expanded(
              child: _CountTile(
                category: Category.work[i],
                count: counts.of(Category.work[i]),
                percent: percentages.of(Category.work[i]),
                onSelect: onSelect,
              ),
            ),
          ],
        ],
      ));
}

class _CountTile extends StatelessWidget {
  const _CountTile({
    required this.category,
    required this.count,
    required this.percent,
    required this.onSelect,
  });

  final Category category;
  final int count;
  final int percent;
  final ValueChanged<Category>? onSelect;

  @override
  Widget build(BuildContext context) {
    final style = categoryStyle(context, category);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final tap = onSelect == null ? null : () => onSelect!(category);
    return Semantics(
      key: Key('count-${category.json}'),
      container: true,
      button: tap != null,
      label: '${style.semanticsLabel(count)}, $percent percent',
      onTap: tap,
      child: ExcludeSemantics(
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: tap,
            excludeFromSemantics: true,
            borderRadius: BorderRadius.circular(Corner.md),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: context.tefteri.rule),
                borderRadius: BorderRadius.circular(Corner.md),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The same fill, hatch or outline as the bar segment.
                  SizedBox(
                    height: 10,
                    child: CategoryBlock(style: style, radius: Corner.sm),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(Space.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(style.icon, size: 18, color: style.accent),
                            const SizedBox(width: Space.xs),
                            Flexible(
                              child: Text('$count',
                                  style: text.headlineSmall,
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ),
                        Text(style.name, style: text.labelLarge),
                        Text('$percent%',
                            style: text.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
