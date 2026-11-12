/// One visual language for the work categories.
///
/// Goal-aligned is the main style: a filled block with a check. Maintenance
/// is muted: a quiet fill with a diagonal hatch and a repeat mark. Off-plan is
/// outlined: an open block with a 2 px accent outline and a compass. Each one
/// also has its own icon and its printed name, so a greyscale picture still
/// tells them apart.
library;

import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import 'statistics_models.dart';

/// How one category looks. Every color comes from the theme.
@immutable
class CategoryStyle {
  /// Creates a style.
  const CategoryStyle({
    required this.category,
    required this.name,
    required this.icon,
    required this.background,
    required this.labelColor,
    required this.iconColor,
    required this.accent,
    this.filled = false,
    this.hatched = false,
    this.hatchColor,
    this.outline,
    this.outlineWidth = 0,
  });

  /// The category.
  final Category category;

  /// The printed name.
  final String name;

  /// The mark that goes with the name.
  final IconData icon;

  /// What the label sits on: the fill, or the page for an outlined style.
  final Color background;

  /// Color of the name and the count.
  final Color labelColor;

  /// Color of the mark.
  final Color iconColor;

  /// Color of the mark on the plain page, where there is no fill under it.
  final Color accent;

  /// The block has a fill.
  final bool filled;

  /// The fill carries a diagonal hatch.
  final bool hatched;

  /// Color of the hatch lines.
  final Color? hatchColor;

  /// Color of the outline, or null for none.
  final Color? outline;

  /// Width of the outline in logical pixels.
  final double outlineWidth;

  /// What a screen reader says: the name and the count.
  String semanticsLabel(int count) =>
      '$name: $count ${count == 1 ? 'task' : 'tasks'}';
}

/// The style of [c] in the current theme.
CategoryStyle categoryStyle(BuildContext context, Category c) {
  final scheme = Theme.of(context).colorScheme;
  final colors = context.tefteri;
  switch (c) {
    case Category.goalAligned:
      return CategoryStyle(
        category: c,
        name: 'Goal-aligned',
        icon: Icons.check_circle_outline,
        background: scheme.primary,
        labelColor: scheme.onPrimary,
        iconColor: scheme.onPrimary,
        accent: scheme.primary,
        filled: true,
      );
    case Category.maintenance:
      return CategoryStyle(
        category: c,
        name: 'Maintenance',
        icon: Icons.repeat,
        background: colors.rule,
        labelColor: scheme.onSurface,
        iconColor: scheme.onSurface,
        accent: scheme.onSurfaceVariant,
        filled: true,
        hatched: true,
        hatchColor: scheme.outline.withValues(alpha: 0.45),
      );
    case Category.offPlan:
      return CategoryStyle(
        category: c,
        name: 'Off-plan',
        icon: Icons.explore_outlined,
        background: colors.paper,
        labelColor: scheme.onSurface,
        iconColor: colors.task,
        accent: colors.task,
        outline: colors.task,
        outlineWidth: 2,
      );
    case Category.hidden:
      return CategoryStyle(
        category: c,
        name: 'Hidden',
        icon: Icons.visibility_off_outlined,
        background: colors.paper,
        labelColor: scheme.onSurfaceVariant,
        iconColor: scheme.onSurfaceVariant,
        accent: scheme.onSurfaceVariant,
        outline: colors.rule,
        outlineWidth: 1,
      );
  }
}

/// Diagonal lines over a block, for the muted style.
class HatchPainter extends CustomPainter {
  /// Creates the painter.
  const HatchPainter(this.color);

  /// Color of the lines.
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    const gap = 6.0;
    for (var x = -size.height; x < size.width; x += gap) {
      canvas.drawLine(
          Offset(x, size.height), Offset(x + size.height, 0), paint);
    }
  }

  @override
  bool shouldRepaint(HatchPainter old) => old.color != color;
}

/// The decoration of a block in [style]: fill, outline, corner. The hatch is
/// a foreground painter ([HatchPainter]) on top.
BoxDecoration categoryDecoration(CategoryStyle style,
        {double radius = Corner.sm}) =>
    BoxDecoration(
      color: style.filled ? style.background : null,
      border: style.outline == null
          ? null
          : Border.all(color: style.outline!, width: style.outlineWidth),
      borderRadius: BorderRadius.circular(radius),
    );

/// A block that wears [style]: fill, hatch and outline.
class CategoryBlock extends StatelessWidget {
  /// Creates the block around [child].
  const CategoryBlock(
      {required this.style, this.child, this.radius = Corner.sm, super.key});

  /// The look.
  final CategoryStyle style;

  /// What sits on the block.
  final Widget? child;

  /// Corner radius.
  final double radius;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: categoryDecoration(style, radius: radius),
        position: DecorationPosition.background,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: CustomPaint(
            painter: style.hatched ? HatchPainter(style.hatchColor!) : null,
            child: child ?? const SizedBox.expand(),
          ),
        ),
      );
}

/// A small label with the mark, the name and, when given, the count.
class CategoryBadge extends StatelessWidget {
  /// Creates a badge.
  const CategoryBadge({required this.category, this.count, super.key});

  /// The category.
  final Category category;

  /// The count to print and to say, or null for the name alone.
  final int? count;

  @override
  Widget build(BuildContext context) {
    final style = categoryStyle(context, category);
    final text = Theme.of(context).textTheme;
    final label = text.labelLarge?.copyWith(color: style.labelColor);
    return Semantics(
      container: true,
      label: count == null ? style.name : style.semanticsLabel(count!),
      child: ExcludeSemantics(
        child: CategoryBlock(
          style: style,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: Space.sm, vertical: Space.xs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(style.icon, size: 16, color: style.iconColor),
                const SizedBox(width: Space.xs),
                Flexible(child: Text(style.name, style: label)),
                if (count != null) ...[
                  const SizedBox(width: Space.sm),
                  Text('$count', style: label),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
