/// A small mark that names the project of a task.
library;

import 'package:flutter/material.dart';

import '../theme/palette.dart';
import 'calendar_color.dart';
import '../theme/tokens.dart';

/// The color of a project: the one that the user chose in the task app
/// ([hex], as `#rrggbb`), or else an accent of the palette that the same name
/// always gets, so that a project is easy to spot in every view.
Color projectAccent(BuildContext context, String name, String? hex) =>
    parseCalendarColor(hex) ?? context.tefteri.projectColor(name);

/// A dot in the color of the project [name].
class ProjectDot extends StatelessWidget {
  /// Creates a dot for the project [name]; [color] is its color in the task
  /// app, as `#rrggbb`, when it has one.
  const ProjectDot({required this.name, this.color, this.size = 10, super.key});

  /// Name of the project.
  final String name;

  /// The color of the project in the task app (`#rrggbb`), or null.
  final String? color;

  /// Width and height.
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: projectAccent(context, name, color),
          shape: BoxShape.circle,
        ),
      );
}

/// The dot and the name of a project, in one line.
class ProjectChip extends StatelessWidget {
  /// Creates a chip for the project [name]; [color] is its color in the task
  /// app, as `#rrggbb`, when it has one.
  const ProjectChip({required this.name, this.color, super.key});

  /// Name of the project.
  final String name;

  /// The color of the project in the task app (`#rrggbb`), or null.
  final String? color;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ProjectDot(name: name, color: color, size: 8),
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
  /// Creates a card for the project [name]; [color] is its color in the task
  /// app, as `#rrggbb`, when it has one.
  const ProjectCard(
      {required this.name, required this.child, this.color, super.key});

  /// Name of the project.
  final String name;

  /// The color of the project in the task app (`#rrggbb`), or null.
  final String? color;

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
              child: ColoredBox(color: projectAccent(context, name, color)),
            ),
          ],
        ),
      );
}
