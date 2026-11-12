/// The completed tasks behind a count, loaded page by page.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/open_url.dart';
import '../../core/project_chip.dart';
import '../../theme/theme.dart';
import '../projects/term_hint.dart';
import '../weekly/weekly_widgets.dart';
import 'category_style.dart';
import 'statistics_models.dart';
import 'statistics_providers.dart';

/// How near the end of the list a scroll must come before the next page
/// starts to load.
const double _loadAhead = 600;

/// A list of completed tasks for [query].
///
/// With `order: 'project'` the tasks sit under the name of their project; with
/// `newest` each row names its project. The list asks for one page at a time,
/// on "Show more" and, when [scrollable], when a scroll comes near the end.
/// It has no cap: every task can be reached.
class CategoryTaskList extends ConsumerStatefulWidget {
  /// Creates the list. With [scrollable] it scrolls itself and needs a height;
  /// otherwise it is as tall as its tasks and the page around it scrolls.
  const CategoryTaskList(
      {required this.query,
      this.scrollable = false,
      this.showHints = true,
      super.key});

  /// Which tasks.
  final TaskListQuery query;

  /// Whether to explain "unsorted" above the tasks. A page that already has
  /// the category card leaves it out, so the word is explained once.
  final bool showHints;

  /// Whether the list scrolls and loads the next page on its own.
  final bool scrollable;

  @override
  ConsumerState<CategoryTaskList> createState() => _CategoryTaskListState();
}

class _CategoryTaskListState extends ConsumerState<CategoryTaskList> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoad);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _maybeLoad() {
    if (!widget.scrollable || !_scroll.hasClients) return;
    final state = ref.read(taskListProvider(widget.query));
    if (state.loading || state.error != null || !state.hasMore) return;
    if (_scroll.position.extentAfter < _loadAhead) {
      ref.read(taskListProvider(widget.query).notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(taskListProvider(widget.query));
    final ctrl = ref.read(taskListProvider(widget.query).notifier);
    if (widget.scrollable) {
      // A short page does not fill the window, so no scroll would ever come.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeLoad();
      });
    }
    if (state.first && state.loading) {
      return const Padding(padding: EdgeInsets.all(Space.xl), child: Loading());
    }
    if (state.items.isEmpty && state.error != null) {
      return _Problem(message: state.error!, onRetry: ctrl.retry);
    }
    if (state.items.isEmpty) {
      return const EmptyState(message: 'No tasks here.');
    }
    final rows = _rows(context, state);
    final footer =
        _Footer(state: state, onMore: ctrl.loadMore, onRetry: ctrl.retry);
    if (widget.scrollable) {
      return ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.all(Space.lg),
        itemCount: rows.length + 1,
        itemBuilder: (_, i) => i < rows.length ? rows[i] : footer,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [...rows, footer],
    );
  }

  List<Widget> _rows(BuildContext context, TaskListState state) {
    final byProject = widget.query.order == 'project';
    final rows = <Widget>[];
    if (widget.showHints && state.items.any((t) => t.unsorted)) {
      rows.add(const TermHint(
          id: 'category-unsorted',
          title: 'What this word means',
          terms: unsortedTaskTerms));
    }
    String? current;
    for (final t in state.items) {
      if (byProject && t.project.name != current) {
        current = t.project.name;
        rows.add(_ProjectHeader(project: t.project));
      }
      rows.add(_TaskRow(task: t, showProject: !byProject));
    }
    return rows;
  }
}

class _ProjectHeader extends StatelessWidget {
  const _ProjectHeader({required this.project});

  final StatProject project;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      key: Key('group-${project.name}'),
      padding: const EdgeInsets.only(top: Space.md, bottom: Space.xs),
      child: Row(
        children: [
          ProjectDot(name: project.name, color: project.color),
          const SizedBox(width: Space.sm),
          Flexible(
              child: Text(project.name,
                  style: text.titleSmall, overflow: TextOverflow.ellipsis)),
          if (project.orphaned) ...[
            const SizedBox(width: Space.sm),
            const _Note('no longer in your task app'),
          ],
        ],
      ),
    );
  }
}

/// A small outlined word, such as "Unsorted".
class _Note extends StatelessWidget {
  const _Note(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: context.tefteri.rule),
          borderRadius: BorderRadius.circular(Corner.sm),
        ),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: Space.xs, vertical: 1),
          child: Text(text,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      );
}

class _TaskRow extends ConsumerWidget {
  const _TaskRow({required this.task, required this.showProject});

  final StatTask task;
  final bool showProject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final style = categoryStyle(context, task.category);
    final day = task.completedDay;
    final quiet = text.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    return Container(
      key: Key('task-row-${task.id}'),
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.tefteri.rule))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            label: style.name,
            child: Icon(style.icon, size: 18, color: style.accent),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.title, style: text.bodyMedium),
                const SizedBox(height: 2),
                Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('${dayName(day)} ${day.day}', style: quiet),
                    if (showProject)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 180),
                        child: ProjectChip(
                            name: task.project.name, color: task.project.color),
                      ),
                    if (showProject && task.project.orphaned)
                      const _Note('no longer in your task app'),
                    if (task.unsorted)
                      _Note('Unsorted', key: Key('unsorted-note-${task.id}')),
                  ],
                ),
              ],
            ),
          ),
          if (task.url != null)
            IconButton(
              tooltip: 'Open in your task app',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.open_in_new, size: 18),
              onPressed: () => ref.read(openUrlProvider)(Uri.parse(task.url!)),
            ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer(
      {required this.state, required this.onMore, required this.onRetry});

  final TaskListState state;
  final VoidCallback onMore;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final quiet = text.bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    final total = state.total ?? state.items.length;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.md),
      child: Column(
        children: [
          Text(
            state.hasMore
                ? 'Showing ${state.items.length} of $total'
                : 'All $total shown',
            key: const Key('list-count'),
            style: quiet,
          ),
          if (state.error != null) ...[
            const SizedBox(height: Space.sm),
            _Problem(
              message: '${state.error!} The tasks above are still here.',
              onRetry: onRetry,
            ),
          ] else if (state.loading)
            const Padding(
                padding: EdgeInsets.all(Space.md),
                child: SizedBox(height: 22, child: Loading()))
          else if (state.hasMore)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: OutlinedButton(
                key: const Key('show-more'),
                onPressed: onMore,
                child: const Text('Show more'),
              ),
            ),
        ],
      ),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium),
          TextButton(
            key: const Key('list-retry'),
            onPressed: onRetry,
            child: const Text('Try again'),
          ),
        ],
      );
}
