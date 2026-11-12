/// Searchable, connection-grouped picker for eligible theme projects.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../theme/theme.dart';
import '../projects/projects_api.dart';
import '../projects/projects_models.dart';
import 'month_api.dart';
import 'month_controller.dart';
import 'month_models.dart';

/// Lets the user edit focus themes without leaving the picker.
class ThemePicker extends ConsumerStatefulWidget {
  /// Creates a picker. [initialSelection] is copied; suggestions are not saved.
  const ThemePicker({
    required this.month,
    required this.initialSelection,
    required this.onSelectionChanged,
    this.onClose,
    super.key,
  });

  /// Month key, `YYYY-MM`.
  final String month;

  /// Themes already selected in the unsaved plan.
  final List<MonthTheme> initialSelection;

  /// Receives the current selection after every change.
  final ValueChanged<List<MonthTheme>> onSelectionChanged;

  /// Optional close action for a dialog or embedded picker.
  final VoidCallback? onClose;

  @override
  ConsumerState<ThemePicker> createState() => _ThemePickerState();
}

class _ThemePickerState extends ConsumerState<ThemePicker> {
  final TextEditingController _search = TextEditingController();
  final Map<String, MonthTheme> _selected = {};
  String _query = '';
  String? _actionError;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    for (final theme in widget.initialSelection) {
      _selected[theme.projectId] = theme;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggle(MonthTheme theme) {
    setState(() {
      if (_selected.containsKey(theme.projectId)) {
        _selected.remove(theme.projectId);
      } else {
        _selected[theme.projectId] = theme;
      }
    });
    widget.onSelectionChanged(_selected.values.toList());
  }

  Future<void> _labelProject(MonthThemePicker picker) async {
    setState(() {
      _working = true;
      _actionError = null;
    });
    try {
      final classification =
          await ref.read(projectsApiProvider).classification();
      final options = [
        for (final connection in classification.connections)
          for (final project in connection.projects)
            if (project.label != ProjectLabel.theme && project.orphaned == null)
              (connection.name, project),
      ];
      if (!mounted) return;
      final selected = await showDialog<ClassifiedProject>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Label a project as theme'),
          content: SizedBox(
            width: 520,
            child: options.isEmpty
                ? const EmptyState(message: 'No live projects can be labelled.')
                : ListView(
                    key: const Key('theme-list'),
                    shrinkWrap: true,
                    children: [
                      for (final (connection, project) in options)
                        ListTile(
                          title: Text(project.name),
                          subtitle: Text(connection),
                          onTap: () => Navigator.pop(context, project),
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
      if (!mounted || selected == null) return;
      await ref
          .read(projectsApiProvider)
          .saveLabels([LabelChange(selected.id, ProjectLabel.theme)]);
      if (!mounted) return;
      ref.invalidate(monthThemesProvider(widget.month));
    } catch (error) {
      if (mounted) setState(() => _actionError = apiErrorMessage(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _createTheme(MonthThemePicker picker) async {
    if (picker.taskConnections.isEmpty) {
      setState(() => _actionError = 'No task connection can create a theme.');
      return;
    }
    final connection = picker.taskConnections.first;
    var themeName = '';
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create a theme'),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Theme name'),
          onChanged: (value) => themeName = value,
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, themeName.trim()),
            child: const Text('Create theme'),
          ),
        ],
      ),
    );
    if (!mounted || result == null || result.isEmpty) return;
    setState(() {
      _working = true;
      _actionError = null;
    });
    try {
      await ref
          .read(monthApiProvider)
          .createTheme('${connection['id']}', result);
      if (!mounted) return;
      ref.invalidate(monthThemesProvider(widget.month));
    } catch (error) {
      if (mounted) setState(() => _actionError = apiErrorMessage(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final choices = ref.watch(monthThemesProvider(widget.month));
    return choices.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(Space.xl),
        child: Loading(),
      ),
      error: (error, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(apiErrorMessage(error)),
          TextButton(
            onPressed: () => ref.invalidate(monthThemesProvider(widget.month)),
            child: const Text('Try again'),
          ),
        ],
      ),
      data: (picker) => _content(picker),
    );
  }

  Widget _content(MonthThemePicker picker) {
    final scheme = Theme.of(context).colorScheme;
    final filtered = picker.themes
        .where((theme) =>
            theme.name.toLowerCase().contains(_query.toLowerCase()) ||
            theme.connectionName.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    final groups = <String, List<MonthTheme>>{};
    for (final theme in filtered) {
      groups.putIfAbsent(theme.connectionName, () => []).add(theme);
    }
    final actions = Wrap(
      spacing: Space.sm,
      runSpacing: Space.xs,
      children: [
        OutlinedButton(
          key: const Key('label-project-as-theme'),
          onPressed: _working ? null : () => _labelProject(picker),
          child: const Text('Label a project as theme'),
        ),
        OutlinedButton(
          key: const Key('create-theme'),
          onPressed: _working ? null : () => _createTheme(picker),
          child: const Text('Create a theme'),
        ),
      ],
    );
    if (picker.themes.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const EmptyState(
            message:
                'A theme project is a long-running home for related work. Label a project or create a theme to add one here.',
            icon: Icons.account_tree_outlined,
          ),
          if (_selected.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.sm),
              child: Text(
                'Still selected: ${_selected.values.map((item) => item.name).join(', ')}',
                key: const Key('kept-theme-selections'),
              ),
            ),
          Center(child: actions),
          if (widget.onClose != null)
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: const Key('theme-picker-done'),
                onPressed: widget.onClose,
                child: const Text('Done'),
              ),
            ),
          if (_actionError != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Text(_actionError!,
                  key: const Key('picker-action-error'),
                  style: TextStyle(color: scheme.error)),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const Key('theme-search'),
          controller: _search,
          decoration: const InputDecoration(
            labelText: 'Search themes',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) => setState(() => _query = value.trim()),
        ),
        const SizedBox(height: Space.sm),
        if (_selected.length < 3 || _selected.length > 5)
          Text(
            _selected.isEmpty
                ? 'Three to five themes is usual. You can save any number.'
                : '${_selected.length} selected. Three to five is usual; you can still save.',
            key: const Key('focus-size-note'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        const SizedBox(height: Space.sm),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: filtered.isEmpty
              ? EmptyState(
                  message: 'No themes match this search.',
                  action: TextButton(
                    key: const Key('clear-theme-search'),
                    onPressed: () {
                      _search.clear();
                      setState(() => _query = '');
                    },
                    child: const Text('Clear search'),
                  ),
                  icon: Icons.search_off,
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final group in groups.entries) ...[
                      Padding(
                        padding: const EdgeInsets.only(
                            top: Space.md, bottom: Space.xs),
                        child: Text(group.key,
                            style: Theme.of(context).textTheme.titleSmall),
                      ),
                      for (final theme in group.value)
                        _ThemeOption(
                          theme: theme,
                          selected: _selected.containsKey(theme.projectId),
                          enabled: !theme.leftThisMonth &&
                              (!theme.inFocus ||
                                  _selected.containsKey(theme.projectId)),
                          onTap: () => _toggle(theme),
                        ),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: Space.sm),
        actions,
        if (_actionError != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: Text(_actionError!,
                key: const Key('picker-action-error'),
                style: TextStyle(color: scheme.error)),
          ),
        if (widget.onClose != null)
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: const Key('theme-picker-done'),
              onPressed: widget.onClose,
              child: const Text('Done'),
            ),
          ),
      ],
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.theme,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final MonthTheme theme;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        checked: selected,
        child: InkWell(
          key: Key('theme-option-${theme.projectId}'),
          borderRadius: BorderRadius.circular(Corner.md),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: Space.sm, vertical: Space.sm),
            child: Row(
              children: [
                Icon(selected
                    ? Icons.check_box_outlined
                    : Icons.check_box_outline_blank),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(theme.name),
                      Text(
                        theme.leftThisMonth
                            ? 'Left this month. Undo that change before adding it again.'
                            : '${theme.lastMonthDone} milestones last month',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
