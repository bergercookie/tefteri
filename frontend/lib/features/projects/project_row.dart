/// One project in the list: its name, what it is, and the chips to change it.
library;

import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import 'label_chips.dart';
import 'project_tree.dart';
import 'projects_models.dart';

/// Width from which the chips sit beside the name instead of under it.
const double projectRowWideWidth = 640;

/// A row of the project list. The row has no rename control for a project
/// that is not live, and none when the task app cannot rename.
class ProjectRow extends StatelessWidget {
  /// Creates the row for [item].
  const ProjectRow({
    required this.item,
    required this.onPick,
    required this.onToggleCollapse,
    required this.onRename,
    required this.onArchive,
    required this.onRestore,
    this.selecting = false,
    this.selected = false,
    this.onSelect,
    super.key,
  });

  /// What to show.
  final ProjectItem item;

  /// A chip was tapped: label, and whether it is the suggestion.
  final void Function(ProjectLabel label, bool isSuggestion) onPick;

  /// The chevron was tapped.
  final VoidCallback onToggleCollapse;

  /// Rename was chosen.
  final VoidCallback onRename;

  /// Archive was chosen.
  final VoidCallback onArchive;

  /// Restore was tapped.
  final VoidCallback onRestore;

  /// True while the user selects several projects.
  final bool selecting;

  /// Whether this row is selected.
  final bool selected;

  /// The checkbox was changed.
  final ValueChanged<bool>? onSelect;

  @override
  Widget build(BuildContext context) {
    final p = item.project;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final colors = context.tefteri;
    final orphan = p.orphaned;
    final isSuggestion = p.label == null && orphan == null;

    final details = <String>[
      if (item.group != GroupKind.themes && item.path.isNotEmpty) item.path,
      if (p.label == ProjectLabel.milestone &&
          orphan == null &&
          item.group != GroupKind.noThemeMilestones)
        item.themeName == null ? 'No theme' : 'Theme: ${item.themeName}',
      if (p.openTasks > 0)
        '${p.openTasks} open ${p.openTasks == 1 ? 'task' : 'tasks'}',
      if (p.subprojects > 0)
        '${p.subprojects} ${p.subprojects == 1 ? 'subproject' : 'subprojects'}',
      if (p.inCommittedPlan) 'In a committed plan',
    ];

    final head = Row(
      children: [
        if (selecting)
          Checkbox(
            key: Key('select-${p.id}'),
            value: selected,
            onChanged: onSelect == null ? null : (v) => onSelect!(v ?? false),
          ),
        SizedBox(
          width: 32,
          child: item.hasChildren
              ? IconButton(
                  key: Key('toggle-${p.id}'),
                  tooltip: item.collapsed
                      ? 'Show what is inside ${p.name}'
                      : 'Hide what is inside ${p.name}',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  icon: Icon(
                      item.collapsed ? Icons.chevron_right : Icons.expand_more),
                  onPressed: onToggleCollapse,
                )
              : null,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: Space.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(p.name,
                        key: Key('name-${p.id}'),
                        style: text.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w500)),
                    if (isSuggestion)
                      Container(
                        key: Key('suggested-${p.id}'),
                        padding: const EdgeInsets.symmetric(
                            horizontal: Space.sm, vertical: 1),
                        decoration: BoxDecoration(
                          border: Border.all(color: scheme.primary),
                          borderRadius: BorderRadius.circular(Corner.pill),
                        ),
                        child: Text('Suggestion',
                            style: text.labelSmall
                                ?.copyWith(color: scheme.primary)),
                      ),
                  ],
                ),
                if (details.isNotEmpty)
                  Text(details.join('  ·  '),
                      key: Key('details-${p.id}'), style: text.bodySmall),
                if (isSuggestion)
                  Text(
                    'Suggested: ${p.proposal.label.title}, because '
                    '${p.proposal.because}.',
                    key: Key('because-${p.id}'),
                    style: text.bodySmall?.copyWith(color: scheme.primary),
                  ),
                if (orphan != null)
                  Text(orphan.explanation,
                      key: Key('orphan-${p.id}'), style: text.bodySmall),
                if (!p.eligible &&
                    orphan == null &&
                    p.label != ProjectLabel.ignored)
                  Row(
                    key: Key('hidden-${p.id}'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.visibility_off_outlined,
                          size: 14, color: colors.task),
                      const SizedBox(width: Space.xs),
                      Flexible(
                        child: Text(
                            'Hidden from planning: a project above it is '
                            'ignored.',
                            style:
                                text.bodySmall?.copyWith(color: colors.task)),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );

    final menu = _menu(context);
    final chips = orphan == null
        ? LabelChips(project: p, onPick: onPick, enabled: !selecting)
        : (orphan.reason == OrphanReason.archived && item.connection.canRestore)
            ? OutlinedButton.icon(
                key: Key('restore-${p.id}'),
                onPressed: onRestore,
                icon: const Icon(Icons.unarchive_outlined, size: 18),
                label: const Text('Restore'),
              )
            : null;

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= projectRowWideWidth;
      final indent = item.depth * Space.xl;
      return Container(
        key: Key('row-${p.id}'),
        padding: EdgeInsets.only(left: indent, right: Space.xs),
        decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.rule))),
        child: wide
            ? Row(children: [
                Expanded(child: head),
                if (chips != null) chips,
                SizedBox(width: 40, child: menu),
              ])
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Expanded(child: head),
                    SizedBox(width: 40, child: menu),
                  ]),
                  if (chips != null)
                    Padding(
                      padding: EdgeInsets.only(
                          left: 32 + (selecting ? 40 : 0), bottom: Space.sm),
                      child:
                          Align(alignment: Alignment.centerLeft, child: chips),
                    ),
                ],
              ),
      );
    });
  }

  Widget? _menu(BuildContext context) {
    final p = item.project;
    if (p.orphaned != null) return null;
    final canRename = item.connection.canRename;
    return PopupMenuButton<String>(
      key: Key('menu-${p.id}'),
      tooltip: 'More for ${p.name}',
      icon: const Icon(Icons.more_vert),
      onSelected: (v) => v == 'rename' ? onRename() : onArchive(),
      itemBuilder: (_) => [
        if (canRename)
          PopupMenuItem(
              key: Key('rename-${p.id}'),
              value: 'rename',
              child: const Text('Rename')),
        PopupMenuItem(
            key: Key('archive-${p.id}'),
            value: 'archive',
            child: const Text('Archive in your task app')),
      ],
    );
  }
}
