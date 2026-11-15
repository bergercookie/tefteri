/// A section title with an info icon that explains the section.
library;

import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Shows [title] in the section style, followed by an info icon. Hover the
/// icon, or tap it on a touch screen, to read [info].
class SectionHeading extends StatelessWidget {
  /// Creates a heading with the explanation [info].
  const SectionHeading({required this.title, required this.info, super.key});

  /// The name of the section.
  final String title;

  /// What the section contains, in one or two sentences.
  final String info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Flexible(child: Text(title, style: theme.textTheme.titleMedium)),
        const SizedBox(width: Space.xs),
        Tooltip(
          message: info,
          triggerMode: TooltipTriggerMode.tap,
          waitDuration: const Duration(milliseconds: 300),
          showDuration: const Duration(seconds: 8),
          child: Icon(
            Icons.info_outline,
            key: Key('info-$title'),
            size: 18,
            semanticLabel: info,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
