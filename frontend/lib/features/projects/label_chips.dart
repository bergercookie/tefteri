/// The four label chips of a project: one tap saves the label.
library;

import 'package:flutter/material.dart';

import 'projects_models.dart';

/// Chips for Theme, Milestone, Routine and Ignored. The saved label is
/// filled. While the project has no label, its suggestion is outlined and
/// marked with a spark, and a tap on it accepts the suggestion.
class LabelChips extends StatelessWidget {
  /// Creates the chips for project [project].
  const LabelChips({
    required this.project,
    required this.onPick,
    this.enabled = true,
    super.key,
  });

  /// The project the chips belong to.
  final ClassifiedProject project;

  /// Called with the chosen label and whether it is the suggestion.
  final void Function(ProjectLabel label, bool isSuggestion) onPick;

  /// False while a change is being saved or the project is not live.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final l in ProjectLabel.values) _chip(context, scheme, l),
      ],
    );
  }

  Widget _chip(BuildContext context, ColorScheme scheme, ProjectLabel l) {
    final selected = project.label == l;
    final suggested = project.label == null && project.proposal.label == l;
    final text = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      selected: selected,
      label: suggested
          ? '${l.title}, suggested for ${project.name}'
          : '${l.title} for ${project.name}',
      child: ExcludeSemantics(
        child: ChoiceChip(
          key: Key('chip-${project.id}-${l.name}'),
          selected: selected,
          materialTapTargetSize: MaterialTapTargetSize.padded,
          avatar: suggested
              ? Icon(Icons.auto_awesome, size: 14, color: scheme.primary)
              : null,
          labelPadding: const EdgeInsets.symmetric(horizontal: 2),
          label: Text(l.title),
          labelStyle: suggested
              ? text.labelMedium?.copyWith(color: scheme.primary)
              : null,
          side: BorderSide(
            color: suggested ? scheme.primary : scheme.outlineVariant,
            width: suggested ? 1.5 : 1,
          ),
          tooltip: suggested
              ? 'Accept the suggestion: ${l.title}'
              : 'Label as ${l.title}: ${l.sentence}',
          // The saved label stays enabled, so it keeps its full contrast.
          onSelected: enabled
              ? (_) {
                  if (!selected) onPick(l, suggested);
                }
              : null,
        ),
      ),
    );
  }
}
