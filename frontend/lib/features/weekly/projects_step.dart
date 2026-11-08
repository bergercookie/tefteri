/// Step 2: choose up to three projects, or create a subproject.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../theme/theme.dart';
import 'weekly_api.dart';
import 'weekly_models.dart';
import 'weekly_widgets.dart';

/// Lets the user pick the projects of the week and add a new subproject.
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
  String _query = '';

  WeeklyPlan? get _plan => widget.state.plan;
  bool get _locked => _plan?.committed ?? false;
  int get _max => _plan?.maxProjects ?? 3;
  int get _count => _plan?.projects.length ?? 0;
  bool get _full => _count >= _max;

  Future<void> _add(WeeklyCandidate c) async {
    await widget.actions
        .run((api) => api.addProject(widget.actions.week, c.containerId));
    ref.invalidate(weeklyCandidatesProvider);
  }

  Future<void> _remove(WeeklyProject p) async {
    await widget.actions
        .run((api) => api.removeProject(widget.actions.week, p.id));
    ref.invalidate(weeklyCandidatesProvider);
  }

  Future<void> _archive(WeeklyCandidate c) async {
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
    ref.invalidate(weeklyCandidatesProvider);
  }

  Future<void> _newSubproject(
      List<WeeklyCandidate> all, String? parentId) async {
    final result = await showDialog<({String parent, String name})>(
      context: context,
      builder: (_) =>
          NewSubprojectDialog(candidates: all, initialParent: parentId),
    );
    if (result == null) return;
    await widget.actions.run((api) =>
        api.createSubproject(widget.actions.week, result.parent, result.name));
    ref.invalidate(weeklyCandidatesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final candidates = ref.watch(weeklyCandidatesProvider(widget.actions.week));
    final projects = _plan?.projects ?? const <WeeklyProject>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StepHeading(
          title: 'Choose up to $_max projects',
          subtitle: 'Pick what you want to move forward this week. '
              'Fewer projects means more of them get done.',
        ),
        Text('$_count of $_max chosen',
            key: const Key('chosen-count'),
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: Space.sm),
        for (var i = 0; i < _max; i++)
          i < projects.length
              ? _chosen(context, projects[i])
              : _emptySlot(context, i),
        const SizedBox(height: Space.lg),
        candidates.when(
          loading: () => const Padding(
              padding: EdgeInsets.all(Space.xl), child: Loading()),
          error: (e, _) =>
              Text(apiErrorMessage(e), key: const Key('candidates-error')),
          data: (all) => _picker(context, all),
        ),
        StepFooter(
          onBack: widget.onBack,
          nextLabel: 'Give tasks a day',
          onNext: _count == 0 ? null : widget.onNext,
          hint: _count == 0 ? 'Choose at least one project to go on.' : null,
        ),
      ],
    );
  }

  Widget _emptySlot(BuildContext context, int i) {
    final colors = context.tefteri;
    return Container(
      key: Key('slot-$i'),
      margin: const EdgeInsets.only(bottom: Space.sm),
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        border: Border.all(color: colors.rule),
        borderRadius: BorderRadius.circular(Corner.lg),
      ),
      child: Text('Project ${i + 1}: choose one below',
          style: Theme.of(context).textTheme.bodySmall),
    );
  }

  Widget _chosen(BuildContext context, WeeklyProject p) {
    final text = Theme.of(context).textTheme;
    return Card(
      key: Key('chosen-${p.id}'),
      child: Padding(
        padding:
            const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.sm, Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name, style: text.titleMedium),
                      Text(
                        p.openTasks == 0
                            ? 'No open tasks yet'
                            : plural(p.openTasks, 'open task'),
                        key: Key('chosen-tasks-${p.id}'),
                        style: text.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (p.createdHere)
                  const Chip(
                      label: Text('New'), visualDensity: VisualDensity.compact),
                if (!_locked)
                  IconButton(
                    key: Key('remove-${p.id}'),
                    tooltip: 'Remove ${p.name} from the week',
                    icon: const Icon(Icons.close),
                    onPressed: () => _remove(p),
                  ),
              ],
            ),
            if (p.openTasks == 0)
              Padding(
                padding: const EdgeInsets.only(top: Space.sm, right: Space.sm),
                child: NoTasksNotice(project: p, actions: widget.actions),
              ),
          ],
        ),
      ),
    );
  }

  Widget _picker(BuildContext context, List<WeeklyCandidate> all) {
    final text = Theme.of(context).textTheme;
    if (all.isEmpty) {
      return const EmptyState(
        icon: Icons.folder_off_outlined,
        messageKey: Key('no-projects'),
        message: 'No projects found. Connect your task app and sync.',
      );
    }
    final q = _query.trim().toLowerCase();
    final shown = [
      for (final c in all)
        if (q.isEmpty || c.path.toLowerCase().contains(q)) c,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpreadRow(
          children: [
            Text('Your projects', style: text.titleMedium),
            OutlinedButton.icon(
              key: const Key('new-subproject'),
              onPressed:
                  _locked || _full ? null : () => _newSubproject(all, null),
              icon: const Icon(Icons.create_new_folder_outlined, size: 18),
              label: const Text('New subproject'),
            ),
          ],
        ),
        const SizedBox(height: Space.sm),
        TextField(
          key: const Key('project-search'),
          onChanged: (v) => setState(() => _query = v),
          decoration: const InputDecoration(
            hintText: 'Search projects',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: Space.sm),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Text('No project matches "${_query.trim()}".',
                key: const Key('no-match'), style: text.bodySmall),
          ),
        for (final c in shown) _candidate(context, c, all),
      ],
    );
  }

  Widget _candidate(
      BuildContext context, WeeklyCandidate c, List<WeeklyCandidate> all) {
    final text = Theme.of(context).textTheme;
    final colors = context.tefteri;
    final chosen = _plan?.projects.any((p) => p.containerId == c.containerId) ??
        c.selected;
    return Container(
      key: Key('candidate-${c.containerId}'),
      decoration:
          BoxDecoration(border: Border(bottom: BorderSide(color: colors.rule))),
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.path, style: text.bodyMedium),
                Wrap(
                  spacing: Space.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(plural(c.openTasks, 'open task'),
                        style: text.bodySmall),
                    if (c.carriedTasks > 0)
                      Text(
                        '${c.carriedTasks} carried over from last week',
                        key: Key('carried-${c.containerId}'),
                        style: text.bodySmall?.copyWith(color: colors.task),
                      ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            key: Key('archive-${c.containerId}'),
            tooltip: 'Archive ${c.name}',
            icon: const Icon(Icons.archive_outlined),
            onPressed: () => _archive(c),
          ),
          IconButton(
            key: Key('sub-${c.containerId}'),
            tooltip: 'New subproject under ${c.name}',
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: _locked || _full
                ? null
                : () => _newSubproject(all, c.containerId),
          ),
          chosen
              ? Icon(Icons.check_circle,
                  key: Key('chosen-mark-${c.containerId}'),
                  color: colors.done,
                  semanticLabel: 'Chosen')
              : OutlinedButton(
                  key: Key('add-${c.containerId}'),
                  onPressed: _locked || _full ? null : () => _add(c),
                  child: const Text('Add'),
                ),
        ],
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
      message: 'Add tasks to "${project.name}" in your task app. '
          'Tefteri checks every few seconds, and they show up here.',
      actions: [
        if (url != null)
          FilledButton.icon(
            key: Key('open-project-${project.id}'),
            onPressed: () => actions.openUrl(url),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Open the project'),
          ),
      ],
    );
  }
}

/// Asks for the parent project and the name of a new subproject.
class NewSubprojectDialog extends StatefulWidget {
  /// Creates the dialog; [initialParent] is a candidate's container id.
  const NewSubprojectDialog(
      {required this.candidates, this.initialParent, super.key});

  /// Projects that can be the parent.
  final List<WeeklyCandidate> candidates;

  /// The parent to start with.
  final String? initialParent;

  @override
  State<NewSubprojectDialog> createState() => _NewSubprojectDialogState();
}

class _NewSubprojectDialogState extends State<NewSubprojectDialog> {
  final _name = TextEditingController();
  late String _parent =
      widget.initialParent ?? widget.candidates.first.containerId;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop((parent: _parent, name: name));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New subproject'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              key: const Key('parent-project'),
              initialValue: _parent,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Inside project'),
              items: [
                for (final c in widget.candidates)
                  DropdownMenuItem(value: c.containerId, child: Text(c.path)),
              ],
              onChanged: (v) => setState(() => _parent = v ?? _parent),
            ),
            const SizedBox(height: Space.md),
            TextField(
              key: const Key('subproject-name'),
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name'),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: Space.sm),
            Text(
              'It is created in your task app. You add its tasks there.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('subproject-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('subproject-create'),
          onPressed: _submit,
          child: const Text('Create and add'),
        ),
      ],
    );
  }
}
