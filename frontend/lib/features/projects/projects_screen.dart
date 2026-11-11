/// The Projects screen: tells Tefteri what each project is for.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_error.dart';
import '../../core/shell.dart';
import '../../theme/theme.dart';
import '../settings/sync_controller.dart';
import 'effect_dialog.dart';
import 'project_row.dart';
import 'project_tree.dart';
import 'projects_api.dart';
import 'projects_controller.dart';
import 'projects_models.dart';
import 'rename_dialog.dart';
import 'term_hint.dart';

/// Lets the user check the suggested labels, change them with one tap, rename
/// projects and see what is no longer in the task app.
class ProjectsScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const ProjectsScreen({super.key});

  @override
  ConsumerState<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends ConsumerState<ProjectsScreen> {
  final _search = TextEditingController();
  String _query = '';
  final Set<String> _collapsed = {};
  final Set<GroupKind> _collapsedGroups = {GroupKind.orphaned};
  bool _selecting = false;
  final Set<String> _selected = {};
  bool _showRecent = false;
  String? _error;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  ClassificationController get _ctrl =>
      ref.read(classificationProvider.notifier);

  void _fail(Object e, String what) {
    if (!mounted) return;
    setState(() => _error = projectsError(e, what));
  }

  void _note(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Runs an undo and tells the user what happened.
  Future<void> _undo(RecentChange change) async {
    final ctrl = _ctrl;
    try {
      await ctrl.undo(change);
      if (mounted) {
        setState(() => _error = null);
        _note('Undone.');
      }
    } on DioException catch (e) {
      _fail(e, 'undo "${change.text}"');
    }
  }

  void _offerUndo(String message, RecentChange? change) {
    if (change == null) {
      _note(message);
      return;
    }
    showUndoSnackBar(context, message, onUndo: () => _undo(change));
  }

  Future<void> _setOne(
      ClassifiedProject p, ProjectLabel label, bool suggestion) async {
    try {
      final change = await _ctrl.save(
        [LabelChange(p.id, label)],
        source: suggestion ? 'suggestion' : 'user',
        summary: '"${p.name}" labelled ${label.title}.',
      );
      if (!mounted) return;
      setState(() => _error = null);
      _offerUndo('"${p.name}" is now ${_a(label)}.', change);
    } on DioException catch (e) {
      _fail(e, 'save the label of "${p.name}"');
    }
  }

  String _a(ProjectLabel l) => switch (l) {
        ProjectLabel.theme => 'a theme',
        ProjectLabel.milestone => 'a milestone',
        ProjectLabel.maintenance => 'a routine',
        ProjectLabel.ignored => 'ignored',
      };

  /// Shows the effect of [changes], and saves them when the user agrees.
  Future<bool> _bulk(List<LabelChange> changes,
      {required String title,
      required String summary,
      String source = 'user'}) async {
    if (changes.isEmpty) return false;
    final ctrl = _ctrl;
    try {
      final effect = await ctrl.preview(changes, source: source);
      if (!mounted) return false;
      if (effect.changed == 0) {
        _note('Nothing to change: these projects already have that label.');
        return false;
      }
      final ok = await showEffectDialog(context, title: title, effect: effect);
      if (!ok || !mounted) return false;
      final change = await ctrl.save(changes, source: source, summary: summary);
      if (!mounted) return true;
      setState(() => _error = null);
      _offerUndo(summary, change);
      return true;
    } on DioException catch (e) {
      _fail(e, 'save these labels');
      return false;
    }
  }

  Future<void> _acceptAll(Classification c) async {
    final changes = [
      for (final conn in c.connections)
        for (final p in conn.projects)
          if (p.label == null && p.orphaned == null)
            LabelChange(p.id, p.proposal.label),
    ];
    final n = changes.length;
    await _bulk(changes,
        title: 'Accept suggestions',
        summary: n == 1 ? 'Accepted 1 suggestion.' : 'Accepted $n suggestions.',
        source: 'suggestion');
  }

  Future<void> _labelSelected(ProjectLabel label) async {
    final changes = [for (final id in _selected) LabelChange(id, label)];
    final n = changes.length;
    final done = await _bulk(changes,
        title: 'Label ${n == 1 ? '1 project' : '$n projects'} as '
            '${label.title}',
        summary: n == 1
            ? '1 project labelled ${label.title}.'
            : '$n projects labelled ${label.title}.');
    if (done && mounted) {
      setState(() {
        _selected.clear();
        _selecting = false;
      });
    }
  }

  Future<void> _rename(ProjectItem it) async {
    final ctrl = _ctrl;
    final p = it.project;
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => RenameDialog(
        currentName: p.name,
        save: (name) async {
          try {
            await ctrl.rename(p.id, name);
            return null;
          } on DioException catch (e) {
            return projectsError(e, 'rename "${p.name}"');
          }
        },
      ),
    );
    if (done == true && mounted) _note('Renamed to the new name.');
  }

  Future<void> _archive(ProjectItem it) async {
    final p = it.project;
    final canRestore = it.connection.canRestore;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('project-archive-confirm'),
        title: Text('Archive "${p.name}"?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tefteri archives the project in your task app'
                '${p.subprojects > 0 ? ', with the ${p.subprojects} '
                    '${p.subprojects == 1 ? 'project' : 'projects'} inside it' : ''}.'),
            const SizedBox(height: Space.sm),
            const Text('It is hidden from the planning pickers. Its label and '
                'history are kept, and it moves to "No longer in your task '
                'app".'),
            const SizedBox(height: Space.sm),
            Text(
              canRestore
                  ? 'You can undo this right after, or restore it later from '
                      'that group.'
                  : 'Your task app cannot restore a project from Tefteri. To '
                      'bring it back, restore it in your task app.',
              key: const Key('archive-restore-note'),
            ),
          ],
        ),
        actions: [
          TextButton(
              key: const Key('project-archive-cancel'),
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              key: const Key('project-archive-yes'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Archive')),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    try {
      final change = await _ctrl.archive(p);
      if (!mounted) return;
      setState(() => _error = null);
      _offerUndo('Archived "${p.name}".', canRestore ? change : null);
    } on DioException catch (e) {
      _fail(e, 'archive "${p.name}"');
    }
  }

  Future<void> _restore(ProjectItem it) async {
    try {
      await _ctrl.restore(it.project.id);
      if (mounted) {
        setState(() => _error = null);
        _note('Restored "${it.project.name}".');
      }
    } on DioException catch (e) {
      _fail(e, 'restore "${it.project.name}"');
    }
  }

  Future<void> _createTheme() async {
    final made = await createTheme(context, ref);
    if (made) await _ctrl.load();
  }

  Future<void> _syncNow() async {
    await ref.read(syncControllerProvider.notifier).syncAll();
    await _ctrl.load();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SyncState>(syncControllerProvider, (prev, next) {
      if (prev != null && prev.busy && !next.busy) {
        _ctrl.load();
        ref.invalidate(unsortedCountProvider);
      }
    });
    final data = ref.watch(classificationProvider);
    return AppShell(
      title: 'Projects',
      body: data.when(
        loading: () => const Loading(),
        error: (e, _) => EmptyState(
          icon: Icons.folder_off_outlined,
          messageKey: const Key('projects-error'),
          message: 'Tefteri could not load your projects. Check your '
              'connection, then try again.',
          action: FilledButton(
            key: const Key('projects-retry'),
            onPressed: () => ref.invalidate(classificationProvider),
            child: const Text('Try again'),
          ),
        ),
        data: _content,
      ),
    );
  }

  Widget _content(Classification c) {
    if (c.connections.isEmpty) {
      return EmptyState(
        icon: Icons.link_outlined,
        messageKey: const Key('no-task-app'),
        message: 'No task app is connected yet.',
        action: FilledButton(
          key: const Key('connect-task-app'),
          onPressed: () =>
              GoRouter.maybeOf(context)?.go('/settings/connections'),
          child: const Text('Connect a task app'),
        ),
      );
    }
    if (c.hasNoProjects) {
      return EmptyState(
        icon: Icons.folder_open_outlined,
        messageKey: const Key('no-projects-yet'),
        message: 'No projects yet. Sync to read them from your task app, or '
            'create your first theme.',
        action: Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          alignment: WrapAlignment.center,
          children: [
            FilledButton.icon(
              key: const Key('sync-now'),
              onPressed: _syncNow,
              icon: const Icon(Icons.sync),
              label: const Text('Sync now'),
            ),
            OutlinedButton.icon(
              key: const Key('create-theme'),
              onPressed: _createTheme,
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('Create a theme'),
            ),
          ],
        ),
      );
    }
    final items = buildTreeItems(c,
        query: _query,
        collapsedNodes: _collapsed,
        collapsedGroups: _collapsedGroups);
    final top = _topWidgets(c);
    final total = [for (final k in c.connections) ...k.projects]
        .where((p) => p.orphaned == null)
        .length;
    return LayoutBuilder(builder: (context, box) {
      final side = ((box.maxWidth - 960) / 2).clamp(Space.lg, double.infinity);
      return FocusTraversalGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Search and the buttons stay in view while a long list scrolls.
            Padding(
              padding: EdgeInsets.fromLTRB(side, Space.md, side, 0),
              child: _toolbar(c, total),
            ),
            Expanded(
              child: ListView.builder(
                key: const Key('projects-list'),
                padding: EdgeInsets.fromLTRB(side, Space.md, side, Space.xxl),
                itemCount: top.length + items.length,
                itemBuilder: (context, i) => i < top.length
                    ? top[i]
                    : _item(context, items[i - top.length]),
              ),
            ),
          ],
        ),
      );
    });
  }

  List<Widget> _topWidgets(Classification c) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final recent = ref.watch(recentChangesProvider);
    final total = [for (final k in c.connections) ...k.projects]
        .where((p) => p.orphaned == null)
        .length;
    return [
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: Space.md),
          child: ErrorBanner(
              message: _error!, onDismiss: () => setState(() => _error = null)),
        ),
      if (c.unsortedCount > 0)
        Container(
          key: const Key('accept-card'),
          margin: const EdgeInsets.only(bottom: Space.lg),
          padding: const EdgeInsets.all(Space.lg),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(Corner.md),
          ),
          child: Wrap(
            spacing: Space.lg,
            runSpacing: Space.md,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.unsortedCount == 1
                          ? '1 project needs a label'
                          : '${c.unsortedCount} projects need a label',
                      key: const Key('unsorted-count'),
                      style: text.titleMedium
                          ?.copyWith(color: scheme.onPrimaryContainer),
                    ),
                    const SizedBox(height: Space.xs),
                    Text(
                      'Tefteri has suggested a label for each one, marked '
                      '"Suggestion" below. If they look right, accept them '
                      'all. You can still change any project afterwards. '
                      'Nothing changes in your task app.',
                      style: text.bodyMedium
                          ?.copyWith(color: scheme.onPrimaryContainer),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                key: const Key('accept-suggestions'),
                onPressed: () => _acceptAll(c),
                icon: const Icon(Icons.check),
                label: const Text('Accept suggestions'),
              ),
            ],
          ),
        )
      else
        Padding(
          padding: const EdgeInsets.only(bottom: Space.md),
          child: Row(
            key: const Key('all-sorted'),
            children: [
              Icon(Icons.check_circle_outline,
                  size: 18, color: context.tefteri.done),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  total == 1
                      ? 'Your project is labelled.'
                      : 'All $total projects are labelled. Change any of '
                          'them with one tap.',
                  style: text.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      const TermHint(
          id: 'labels', title: 'What the labels mean', terms: projectTerms),
      if (_selecting) _selectBar(),
      if (recent.isNotEmpty) _recentChanges(recent),
    ];
  }

  static final _tight = TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm));

  Widget _toolbar(Classification c, int total) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('project-search'),
          controller: _search,
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText:
                'Search ${total == 1 ? 'your project' : 'your $total projects'}',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    key: const Key('project-search-clear'),
                    tooltip: 'Clear the search',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      _search.clear();
                      _query = '';
                    }),
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.xs),
          child: Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton.icon(
                style: _tight,
                key: const Key('select-toggle'),
                onPressed: () => setState(() {
                  _selecting = !_selecting;
                  _selected.clear();
                }),
                icon: Icon(_selecting ? Icons.close : Icons.checklist_outlined,
                    size: 18),
                label: Text(_selecting ? 'Stop' : 'Select'),
              ),
              TextButton.icon(
                style: _tight,
                key: const Key('collapse-all'),
                onPressed: () => setState(() {
                  final ids = collapsibleIds(c);
                  if (_collapsed.containsAll(ids)) {
                    _collapsed.clear();
                  } else {
                    _collapsed.addAll(ids);
                  }
                }),
                icon: const Icon(Icons.unfold_less, size: 18),
                label: Text(_collapsed.isEmpty ? 'Collapse all' : 'Expand all'),
              ),
              TextButton.icon(
                style: _tight,
                key: const Key('create-theme'),
                onPressed: _createTheme,
                icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                label: const Text('New theme'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _selectBar() {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final n = _selected.length;
    return Container(
      key: const Key('select-bar'),
      margin: const EdgeInsets.only(bottom: Space.md),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(Corner.md),
      ),
      child: Wrap(
        spacing: Space.sm,
        runSpacing: Space.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(n == 0 ? 'Tick the projects to change' : '$n selected',
              key: const Key('select-count'),
              style: text.titleSmall
                  ?.copyWith(color: scheme.onSecondaryContainer)),
          for (final l in ProjectLabel.values)
            OutlinedButton(
              key: Key('bulk-${l.name}'),
              onPressed: n == 0 ? null : () => _labelSelected(l),
              child: Text('Label as ${l.title}'),
            ),
        ],
      ),
    );
  }

  Widget _recentChanges(List<RecentChange> recent) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(
            key: const Key('recent-toggle'),
            onPressed: () => setState(() => _showRecent = !_showRecent),
            icon: Icon(_showRecent ? Icons.expand_more : Icons.chevron_right,
                size: 18),
            label: Text('Recent changes (${recent.length})'),
          ),
          if (_showRecent)
            for (var i = 0; i < recent.length; i++)
              Row(
                key: Key('recent-$i'),
                children: [
                  const SizedBox(width: Space.xl),
                  Expanded(
                    child: Text(recent[i].text,
                        style: text.bodyMedium?.copyWith(
                            decoration: recent[i].undone
                                ? TextDecoration.lineThrough
                                : null)),
                  ),
                  if (recent[i].undone)
                    Text('Undone', style: text.bodySmall)
                  else
                    TextButton(
                      key: Key('recent-undo-$i'),
                      onPressed: () => _undo(recent[i]),
                      child: const Text('Undo'),
                    ),
                ],
              ),
        ],
      ),
    );
  }

  Widget _item(BuildContext context, TreeItem item) => switch (item) {
        ConnectionItem() => Padding(
            padding: const EdgeInsets.only(top: Space.lg),
            child: Text(item.name,
                style: Theme.of(context).textTheme.headlineSmall),
          ),
        GroupItem() => _groupHeader(context, item),
        NoMatchItem() => Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Text(
                'No project matches "${item.query}". Check the '
                'spelling, or clear the search.',
                key: const Key('no-match'),
                style: Theme.of(context).textTheme.bodyMedium),
          ),
        ProjectItem() => ProjectRow(
            key: ValueKey('item-${item.project.id}'),
            item: item,
            selecting: _selecting,
            selected: _selected.contains(item.project.id),
            onSelect: (v) => setState(() => v
                ? _selected.add(item.project.id)
                : _selected.remove(item.project.id)),
            onPick: (label, suggestion) =>
                _setOne(item.project, label, suggestion),
            onToggleCollapse: () => setState(() {
              if (!_collapsed.remove(item.project.id)) {
                _collapsed.add(item.project.id);
              }
            }),
            onRename: () => _rename(item),
            onArchive: () => _archive(item),
            onRestore: () => _restore(item),
          ),
      };

  Widget _groupHeader(BuildContext context, GroupItem g) {
    final text = Theme.of(context).textTheme;
    final colors = context.tefteri;
    return Padding(
      padding: const EdgeInsets.only(top: Space.xl),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('group-${g.kind.name}'),
          borderRadius: BorderRadius.circular(Corner.md),
          onTap: () => setState(() {
            if (!_collapsedGroups.remove(g.kind)) _collapsedGroups.add(g.kind);
          }),
          child: Container(
            padding: const EdgeInsets.only(bottom: Space.sm),
            decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: colors.margin))),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4, right: Space.sm),
                  child: Icon(
                      g.collapsed ? Icons.chevron_right : Icons.expand_more),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${g.kind.title} (${g.count})',
                          key: Key('group-title-${g.kind.name}'),
                          style: text.titleLarge),
                      Text(g.kind.sentence,
                          key: Key('group-sentence-${g.kind.name}'),
                          style: text.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
