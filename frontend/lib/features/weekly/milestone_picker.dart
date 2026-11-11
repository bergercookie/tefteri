/// The list of milestones the user can commit to, grouped by theme.
library;

import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import '../projects/term_hint.dart';
import '../projects/unsorted_card.dart';
import 'rescope_nudge.dart';
import 'weekly_models.dart';
import 'weekly_widgets.dart';

/// What a group of the picker holds.
enum PickerGroupKind {
  /// Milestones under one theme.
  theme,

  /// Milestones with no theme above them.
  noTheme,

  /// Projects without a label; picking one labels it milestone.
  unsorted,
}

/// One group of the picker.
@immutable
class PickerGroup {
  /// Creates a group.
  const PickerGroup(this.kind, this.items, {this.theme});

  /// What the group holds.
  final PickerGroupKind kind;

  /// The theme of a theme group.
  final ThemeGroup? theme;

  /// The candidates in it.
  final List<MilestoneCandidate> items;

  /// The theme is in the month's focus (null: no focus data).
  bool? get inFocus => theme?.inFocus;
}

/// Sorts [candidates] into groups: the focus themes first when [themes] says
/// that focus data exists, then the other themes, then "No theme", then
/// "Unsorted". Themes without a milestone stay as empty groups unless [query]
/// is set. [themes] may be null (the call failed): the themes are then read
/// from the candidates.
List<PickerGroup> buildPickerGroups(
    List<MilestoneCandidate> candidates, WeeklyThemes? themes,
    {String query = ''}) {
  final q = query.trim().toLowerCase();
  bool matches(MilestoneCandidate c) =>
      q.isEmpty ||
      c.path.toLowerCase().contains(q) ||
      c.name.toLowerCase().contains(q);
  final known = <String, ThemeGroup>{
    for (final t in themes?.themes ?? const <ThemeGroup>[]) t.id: t,
  };
  // A theme that the themes call did not list (the call failed, or the theme
  // is not eligible any more) still gets a group, so its milestones show.
  for (final c in candidates) {
    final t = c.theme;
    if (t != null && c.kind == 'milestone' && !known.containsKey(t.id)) {
      known[t.id] = ThemeGroup(
          id: t.id, containerId: '', name: t.name, inFocus: c.inFocus);
    }
  }
  var order = known.values.toList();
  if (themes?.focusKnown ?? false) {
    order = [
      ...order.where((t) => t.inFocus == true),
      ...order.where((t) => t.inFocus != true),
    ];
  }
  final groups = <PickerGroup>[];
  for (final t in order) {
    final items = [
      for (final c in candidates)
        if (c.kind == 'milestone' && c.theme?.id == t.id && matches(c)) c,
    ];
    if (items.isEmpty && q.isNotEmpty) continue;
    groups.add(PickerGroup(PickerGroupKind.theme, items, theme: t));
  }
  final none = [
    for (final c in candidates)
      if (c.kind == 'milestone' && c.theme == null && matches(c)) c,
  ];
  if (none.isNotEmpty) groups.add(PickerGroup(PickerGroupKind.noTheme, none));
  final unsorted = [
    for (final c in candidates)
      if (c.unsorted && matches(c)) c,
  ];
  if (unsorted.isNotEmpty) {
    groups.add(PickerGroup(PickerGroupKind.unsorted, unsorted));
  }
  return groups;
}

/// The picker: search, groups, and the inline actions of every empty state.
class MilestonePicker extends StatefulWidget {
  /// Creates the picker.
  const MilestonePicker({
    required this.candidates,
    required this.themes,
    required this.chosenContainerIds,
    required this.locked,
    required this.onAdd,
    required this.onArchive,
    required this.onNewMilestone,
    required this.onCreateTheme,
    super.key,
  });

  /// What can be picked.
  final List<MilestoneCandidate> candidates;

  /// The themes, or null when they could not be read.
  final WeeklyThemes? themes;

  /// Project ids of the milestones already in the plan.
  final Set<String> chosenContainerIds;

  /// The plan is committed: nothing can be added.
  final bool locked;

  /// Adds a candidate to the week.
  final void Function(MilestoneCandidate c) onAdd;

  /// Archives the project of a candidate.
  final void Function(MilestoneCandidate c) onArchive;

  /// Opens the new-milestone dialog, under [theme] when given.
  final void Function(ThemeGroup? theme) onNewMilestone;

  /// Creates a theme.
  final VoidCallback onCreateTheme;

  @override
  State<MilestonePicker> createState() => _MilestonePickerState();
}

class _MilestonePickerState extends State<MilestonePicker> {
  String _query = '';

  List<ThemeGroup> get _themeList {
    final t = widget.themes?.themes ?? const <ThemeGroup>[];
    return [
      for (final g in t)
        if (g.containerId.isNotEmpty) g,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final themes = widget.themes;
    final nothing =
        widget.candidates.isEmpty && (themes?.themes.isEmpty ?? true);
    if (nothing) return _empty(context);
    final groups = buildPickerGroups(widget.candidates, themes, query: _query);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpreadRow(
          children: [
            Text('Milestones you can add', style: text.titleMedium),
            OutlinedButton.icon(
              key: const Key('new-milestone'),
              onPressed: widget.locked || _themeList.isEmpty
                  ? null
                  : () => widget.onNewMilestone(null),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New milestone'),
            ),
          ],
        ),
        const SizedBox(height: Space.sm),
        const TermHint(
          id: 'weekly-picker',
          title: 'Words used here',
          compactTitle: 'What do milestone and done-state mean?',
          compact: true,
          terms: weeklyPickerTerms,
        ),
        const UnsortedCard(quiet: true),
        TextField(
          key: const Key('project-search'),
          onChanged: (v) => setState(() => _query = v),
          decoration: const InputDecoration(
            hintText: 'Search milestones',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: Space.sm),
        if (groups.isEmpty)
          Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Text('No milestone matches "${_query.trim()}".',
                key: const Key('no-match'), style: text.bodySmall),
          ),
        for (final g in groups) _group(context, g),
      ],
    );
  }

  /// Nothing to pick and no theme: explain the words and offer the next step.
  Widget _empty(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const UnsortedCard(quiet: true),
        EmptyState(
          icon: Icons.folder_off_outlined,
          messageKey: const Key('no-projects'),
          message: 'No milestone to plan yet.',
          action: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Text(
                  'A theme is a long-running home for related work. A '
                  'milestone is a small project under a theme that you can '
                  'finish in about a week. Label a project as a theme, or '
                  'create one, and then add milestones under it.',
                  key: const Key('picker-explain'),
                  textAlign: TextAlign.center,
                  style: text.bodyMedium,
                ),
              ),
              const SizedBox(height: Space.md),
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton(
                    key: const Key('label-a-theme'),
                    onPressed: () => openProjects(context),
                    child: const Text('Label a project as theme'),
                  ),
                  OutlinedButton(
                    key: const Key('create-a-theme'),
                    onPressed: widget.onCreateTheme,
                    child: const Text('Create a theme'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _group(BuildContext context, PickerGroup g) {
    final text = Theme.of(context).textTheme;
    final colors = context.tefteri;
    final scheme = Theme.of(context).colorScheme;
    final theme = g.theme;
    final focus = g.inFocus == true && (widget.themes?.focusKnown ?? false);
    final (key, title) = switch (g.kind) {
      PickerGroupKind.theme => ('group-${theme!.id}', theme.name),
      PickerGroupKind.noTheme => ('group-no-theme', 'No theme'),
      PickerGroupKind.unsorted => ('group-unsorted', 'Unsorted'),
    };
    return Container(
      key: Key(key),
      margin: const EdgeInsets.only(bottom: Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: Space.md, vertical: Space.sm),
            decoration: BoxDecoration(
              color: focus ? colors.taskContainer : null,
              border: Border(
                  bottom: BorderSide(color: colors.rule),
                  left: focus
                      ? BorderSide(color: colors.task, width: 3)
                      : BorderSide.none),
            ),
            child: SpreadRow(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(child: Text(title, style: text.titleMedium)),
                    if (focus) ...[
                      const SizedBox(width: Space.sm),
                      Text('In focus this month',
                          key: Key('focus-badge-${theme!.id}'),
                          style:
                              text.labelMedium?.copyWith(color: colors.task)),
                    ],
                  ],
                ),
                if (theme != null && theme.containerId.isNotEmpty)
                  TextButton.icon(
                    key: Key('new-milestone-${theme.containerId}'),
                    onPressed: widget.locked
                        ? null
                        : () => widget.onNewMilestone(theme),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New milestone'),
                  ),
              ],
            ),
          ),
          if (g.kind == PickerGroupKind.unsorted)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Text(
                'These projects have no label yet. Picking one labels it '
                'milestone.',
                key: const Key('unsorted-hint'),
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          if (g.kind == PickerGroupKind.noTheme)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Text(
                'These milestones are not under a theme. Closing one cannot '
                'return its tasks anywhere.',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          if (g.items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.md),
              child: Wrap(
                spacing: Space.md,
                runSpacing: Space.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('No milestones under this theme yet.',
                      key: Key('empty-theme-${theme!.id}'),
                      style: text.bodyMedium),
                  if (theme.containerId.isNotEmpty)
                    FilledButton.tonal(
                      key: Key('create-milestone-${theme.containerId}'),
                      onPressed: widget.locked
                          ? null
                          : () => widget.onNewMilestone(theme),
                      child: const Text('Create a milestone'),
                    ),
                ],
              ),
            ),
          for (final c in g.items) _candidate(context, c, g.kind),
        ],
      ),
    );
  }

  Widget _candidate(
      BuildContext context, MilestoneCandidate c, PickerGroupKind kind) {
    final text = Theme.of(context).textTheme;
    final colors = context.tefteri;
    final scheme = Theme.of(context).colorScheme;
    final chosen = widget.chosenContainerIds.contains(c.containerId);
    final quiet = text.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    return Container(
      key: Key('candidate-${c.containerId}'),
      decoration:
          BoxDecoration(border: Border(bottom: BorderSide(color: colors.rule))),
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(kind == PickerGroupKind.theme ? c.name : c.path,
                    style: text.bodyMedium),
                if (c.doneState != null)
                  Text('Done when: ${c.doneState}',
                      key: Key('done-state-${c.containerId}'), style: quiet),
                Wrap(
                  spacing: Space.md,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(plural(c.openTasks, 'open task'),
                        style: text.bodySmall),
                    if (c.parked)
                      Text('Parked',
                          key: Key('parked-${c.containerId}'),
                          style:
                              text.labelMedium?.copyWith(color: colors.task)),
                    if (c.rolloverCount > 0)
                      Text(
                          c.rolloverCount == 1
                              ? 'Rolled over once'
                              : 'Rolled over ${c.rolloverCount} times',
                          key: Key('rollover-${c.containerId}'),
                          style: text.bodySmall),
                    if (c.carriedTasks > 0)
                      Text(
                        '${c.carriedTasks} carried over from last week',
                        key: Key('carried-${c.containerId}'),
                        style: text.bodySmall?.copyWith(color: colors.task),
                      ),
                  ],
                ),
                if (c.decisionOpen)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.xs),
                    child: Text(
                      'The last review left this open. You can decide in the '
                      'next review, or commit it now.',
                      key: Key('decision-open-${c.containerId}'),
                      style: quiet,
                    ),
                  ),
                RescopeNudge(
                    show: c.needsRescope,
                    name: c.name,
                    nudgeKey: Key('rescope-${c.containerId}')),
              ],
            ),
          ),
          IconButton(
            key: Key('archive-${c.containerId}'),
            tooltip: 'Archive ${c.name}',
            icon: const Icon(Icons.archive_outlined),
            onPressed: () => widget.onArchive(c),
          ),
          chosen
              ? Padding(
                  padding: const EdgeInsets.only(top: Space.sm, left: Space.xs),
                  child: Row(
                    key: Key('chosen-mark-${c.containerId}'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle,
                          color: colors.done,
                          size: 20,
                          semanticLabel: 'Chosen'),
                      const SizedBox(width: Space.xs),
                      Text('Already committed', style: text.labelMedium),
                    ],
                  ),
                )
              : OutlinedButton(
                  key: Key('add-${c.containerId}'),
                  onPressed: widget.locked ? null : () => widget.onAdd(c),
                  child: const Text('Add'),
                ),
        ],
      ),
    );
  }
}
