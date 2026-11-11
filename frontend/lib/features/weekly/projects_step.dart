/// Step 2: choose the milestones of the week, or create a milestone.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../theme/theme.dart';
import '../projects/rename_dialog.dart';
import '../projects/term_hint.dart';
import 'cap_notice.dart';
import 'inline_add_task.dart';
import 'milestone_picker.dart';
import 'new_milestone_dialog.dart';
import 'rescope_nudge.dart';
import 'weekly_api.dart';
import 'weekly_models.dart';
import 'weekly_widgets.dart';

/// Lets the user pick the milestones of the week and create a new one.
class ProjectsStep extends ConsumerStatefulWidget {
  /// Creates the step.
  const ProjectsStep({
    required this.state,
    required this.actions,
    required this.onBack,
    required this.onNext,
    super.key,
  });

  /// The loaded week.
  final WeeklyState state;

  /// What the step can ask the screen to do.
  final WeeklyActions actions;

  /// Goes back to the look-back.
  final VoidCallback onBack;

  /// Goes on to giving tasks a day.
  final VoidCallback onNext;

  @override
  ConsumerState<ProjectsStep> createState() => _ProjectsStepState();
}

class _ProjectsStepState extends ConsumerState<ProjectsStep> {
  WeeklyPlan? get _plan => widget.state.plan;
  bool get _locked => _plan?.committed ?? false;

  void _refreshPicker() {
    ref.invalidate(weeklyCandidatesProvider);
    ref.invalidate(weeklyThemesProvider);
  }

  Future<void> _add(MilestoneCandidate c) async {
    await widget.actions
        .run((api) => api.addProject(widget.actions.week, c.containerId));
    _refreshPicker();
  }

  Future<void> _remove(WeeklyProject p) async {
    await widget.actions
        .run((api) => api.removeProject(widget.actions.week, p.id));
    _refreshPicker();
  }

  Future<void> _archive(MilestoneCandidate c) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('archive-confirm'),
        title: Text('Archive "${c.name}"?'),
        content: const Text(
            'The project is archived in your task app, with the projects '
            'inside it. Its tasks leave tefteri. You can restore the project '
            'in your task app.'),
        actions: [
          TextButton(
              key: const Key('archive-cancel'),
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              key: const Key('archive-yes'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Archive')),
        ],
      ),
    );
    if (sure != true) return;
    await widget.actions.run((api) async {
      await api.archiveProject(c.connectionId, c.containerId);
      return api.state(widget.actions.week);
    });
    _refreshPicker();
  }

  Future<void> _newMilestone(List<ThemeGroup> themes, ThemeGroup? under) async {
    final usable = [
      for (final t in themes)
        if (t.containerId.isNotEmpty) t,
    ];
    if (usable.isEmpty) return;
    await showDialog<bool>(
      context: context,
      builder: (_) => NewMilestoneDialog(
        themes: usable,
        initialParent: under?.containerId,
        save: (m) => ref
            .read(weeklyStateProvider(widget.actions.week).notifier)
            .apply((api) => api.createMilestone(
                widget.actions.week, m.parentId, m.name, m.doneState)),
      ),
    );
    _refreshPicker();
  }

  @override
  Widget build(BuildContext context) {
    final week = widget.actions.week;
    final candidates = ref.watch(weeklyCandidatesProvider(week));
    final themes = ref.watch(weeklyThemesProvider(week));
    final projects = _plan?.projects ?? const <WeeklyProject>[];
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepHeading(
          title: 'Choose milestones',
          subtitle: 'A milestone is a small project you can finish in about '
              'a week. Pick what you want to move forward this week. '
              'Fewer milestones usually means more of them get done.',
        ),
        Text(
          projects.isEmpty
              ? 'No milestones chosen yet'
              : '${plural(projects.length, 'milestone')} chosen',
          key: const Key('chosen-count'),
          style: text.titleSmall,
        ),
        CapNotice(count: projects.length, cap: _plan?.milestoneCap ?? 3),
        const SizedBox(height: Space.sm),
        for (final p in projects) _chosen(context, p),
        if (projects.any((p) => p.outsideFocus))
          const TermHint(
            id: 'weekly-outside-focus',
            title: 'Outside focus',
            compact: true,
            terms: outsideFocusTerms,
          ),
        const SizedBox(height: Space.lg),
        candidates.when(
          loading: () => const Padding(
              padding: EdgeInsets.all(Space.xl), child: Loading()),
          error: (e, _) => Column(
            children: [
              Text(apiErrorMessage(e), key: const Key('candidates-error')),
              TextButton(
                key: const Key('candidates-retry'),
                onPressed: _refreshPicker,
                child: const Text('Try again'),
              ),
            ],
          ),
          data: (all) {
            final t = themes.valueOrNull;
            return MilestonePicker(
              candidates: all,
              themes: t,
              chosenContainerIds: {
                for (final p in projects)
                  if (p.containerId != null) p.containerId!,
                for (final c in all)
                  if (c.selected) c.containerId,
              },
              locked: _locked,
              onAdd: _add,
              onArchive: _archive,
              onNewMilestone: (under) =>
                  _newMilestone(t?.themes ?? const [], under),
              onCreateTheme: () async {
                final made = await createTheme(context, ref);
                if (made) _refreshPicker();
              },
            );
          },
        ),
        StepFooter(
          onBack: widget.onBack,
          nextLabel: 'Give tasks a day',
          onNext: widget.onNext,
          hint: projects.isEmpty
              ? 'You can go on without a milestone. A week with none is valid.'
              : null,
        ),
      ],
    );
  }

  Widget _chosen(BuildContext context, WeeklyProject p) {
    final text = Theme.of(context).textTheme;
    final colors = context.tefteri;
    final scheme = Theme.of(context).colorScheme;
    final quiet = text.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    return Card(
      key: Key('chosen-${p.id}'),
      child: Padding(
        padding:
            const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.sm, Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name, style: text.titleMedium),
                      if (p.doneState != null)
                        Text('Done when: ${p.doneState}',
                            key: Key('chosen-done-state-${p.id}'),
                            style: text.bodyMedium),
                      const SizedBox(height: Space.xs),
                      Wrap(
                        spacing: Space.md,
                        runSpacing: Space.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(p.theme?.name ?? 'No theme',
                              key: Key('chosen-theme-${p.id}'),
                              style: text.bodySmall),
                          Text(
                            p.openTasks == 0
                                ? 'No open tasks yet'
                                : plural(p.openTasks, 'open task'),
                            key: Key('chosen-tasks-${p.id}'),
                            style: text.bodySmall,
                          ),
                          if (p.rolloverCount > 0)
                            Text(
                                p.rolloverCount == 1
                                    ? 'Rolled over once'
                                    : 'Rolled over ${p.rolloverCount} times',
                                style: text.bodySmall),
                          OutsideFocusTag(show: p.outsideFocus),
                          if (p.createdHere)
                            Text('New',
                                style: text.labelMedium
                                    ?.copyWith(color: colors.task)),
                        ],
                      ),
                    ],
                  ),
                ),
                if (!_locked)
                  IconButton(
                    key: Key('remove-${p.id}'),
                    tooltip: 'Remove ${p.name} from the week',
                    icon: const Icon(Icons.close),
                    onPressed: () => _remove(p),
                  ),
              ],
            ),
            if (p.orphaned)
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: Text(
                    'This project is no longer in your task app. Tefteri keeps '
                    'its name and history.',
                    key: Key('orphaned-${p.id}'),
                    style: quiet),
              ),
            if (p.notice == 'relabelled')
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: Text(
                    'This project got another label after you chose it. It '
                    'stays in this week, and is not offered as a milestone '
                    'next time.',
                    key: Key('relabelled-${p.id}'),
                    style: quiet),
              ),
            RescopeNudge(
                show: p.needsRescope,
                name: p.name,
                nudgeKey: Key('rescope-${p.id}')),
            if (p.openTasks == 0 && !_locked)
              Padding(
                padding: const EdgeInsets.only(top: Space.sm, right: Space.sm),
                child: NoTasksNotice(project: p, actions: widget.actions),
              ),
          ],
        ),
      ),
    );
  }
}

/// Tells the user to add tasks in the task app, which tefteri then picks up.
class NoTasksNotice extends StatelessWidget {
  /// Creates the note for [project].
  const NoTasksNotice(
      {required this.project, required this.actions, super.key});

  /// The project without open tasks.
  final WeeklyProject project;

  /// What the note can ask the screen to do.
  final WeeklyActions actions;

  @override
  Widget build(BuildContext context) {
    final url = project.url;
    return Notice(
      key: Key('no-tasks-${project.id}'),
      icon: Icons.hourglass_empty,
      message: 'Add a task here, or add tasks to "${project.name}" in your '
          'task app. Tefteri checks every few seconds, and they show up here.',
      actions: [
        if (url != null)
          OutlinedButton.icon(
            key: Key('open-project-${project.id}'),
            onPressed: () => actions.openUrl(url),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Open the project'),
          ),
      ],
      below: InlineAddTask(project: project, actions: actions),
    );
  }
}
