/// A small mark that names the project of a task.
library;

import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../theme/tokens.dart';

/// A dot in the accent of the project [name]. The same name always has the
/// same accent, so a project is easy to spot in every view.
class ProjectDot extends StatelessWidget {
  /// Creates a dot for the project [name].
  const ProjectDot({required this.name, this.size = 10, super.key});

  /// Name of the project.
  final String name;

  /// Width and height.
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: context.tefteri.projectColor(name),
          shape: BoxShape.circle,
        ),
      );
}

/// The dot and the name of a project, in one line.
class ProjectChip extends StatelessWidget {
  /// Creates a chip for the project [name].
  const ProjectChip({required this.name, super.key});

  /// Name of the project.
  final String name;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ProjectDot(name: name, size: 8),
          const SizedBox(width: Space.xs),
          Flexible(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      );
}

/// A card for the tasks of one project, with a stripe in the accent of the
/// project on its left edge.
class ProjectCard extends StatelessWidget {
  /// Creates a card for the project [name].
  const ProjectCard({required this.name, required this.child, super.key});

  /// Name of the project.
  final String name;

  /// What the card holds.
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Padding(padding: const EdgeInsets.only(left: 5), child: child),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 5,
              child: ColoredBox(color: context.tefteri.projectColor(name)),
            ),
          ],
        ),
      );
}
