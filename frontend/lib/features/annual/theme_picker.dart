/// The theme picker of a key result (FR-012). It lists only eligible themes,
/// and offers "Label a project as theme" and "Create a theme" inline, so the
/// user never leaves the planning screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../theme/theme.dart';
import '../projects/projects_api.dart';
import '../projects/projects_models.dart';
import 'annual_controller.dart';
import 'annual_models.dart';
import 'annual_term_hint.dart';
import 'create_theme_dialog.dart';

/// Opens the picker with [selected] ticked. Answers the chosen themes, or null
/// when the user cancels. With [startWithCreate] the create dialog opens at
/// once (the "Create a theme" action of a flag).
Future<List<ThemeOption>?> pickThemes(BuildContext context,
        {List<ThemeOption> selected = const [],
        bool startWithCreate = false}) =>
    showDialog<List<ThemeOption>>(
      context: context,
      builder: (_) => AnnualThemePicker(
          selected: selected, startWithCreate: startWithCreate),
    );

/// The picker dialog.
class AnnualThemePicker extends ConsumerStatefulWidget {
  /// Creates the picker.
  const AnnualThemePicker(
      {this.selected = const [], this.startWithCreate = false, super.key});

  /// The themes ticked at the start.
  final List<ThemeOption> selected;

  /// Opens the create dialog at once.
  final bool startWithCreate;

  @override
  ConsumerState<AnnualThemePicker> createState() => _AnnualThemePickerState();
}

class _AnnualThemePickerState extends ConsumerState<AnnualThemePicker> {
  late final Map<String, ThemeOption> _picked = {
    for (final t in widget.selected) t.projectId: t,
  };
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.startWithCreate) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final choices = await ref.read(themeChoicesProvider.future);
        if (mounted) await _create(choices);
      });
    }
  }

  void _toggle(ThemeOption t) => setState(() {
        if (_picked.remove(t.projectId) == null) _picked[t.projectId] = t;
      });

  Future<void> _create(ThemeChoices choices) async {
    final made = await showCreateThemeDialog(context, choices.taskConnections);
    if (made == null || !mounted) return;
    ref.invalidate(themeChoicesProvider);
    setState(() => _picked[made.projectId] = made);
  }

  Future<void> _label() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final classification =
          await ref.read(projectsApiProvider).classification();
      final options = [
        for (final c in classification.connections)
          for (final p in c.projects)
            if (p.label != ProjectLabel.theme && p.orphaned == null)
              (c.name, p),
      ];
      if (!mounted) return;
      setState(() => _busy = false);
      final chosen = await showDialog<ClassifiedProject>(
        context: context,
        builder: (context) => _LabelDialog(options: options),
      );
      if (chosen == null || !mounted) return;
      setState(() => _busy = true);
      await ref
          .read(projectsApiProvider)
          .saveLabels([LabelChange(chosen.id, ProjectLabel.theme)]);
      if (!mounted) return;
      ref.invalidate(themeChoicesProvider);
      setState(() {
        _busy = false;
        _picked[chosen.id] =
            ThemeOption(projectId: chosen.id, name: chosen.name);
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = apiErrorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final choices = ref.watch(themeChoicesProvider);
    return AlertDialog(
      key: const Key('theme-picker'),
      title: const Text('Link themes'),
      content: SizedBox(
        width: 480,
        child: choices.when(
          loading: () => const SizedBox(height: 120, child: Loading()),
          error: (e, _) => EmptyState(
            message: apiErrorMessage(e),
            action: TextButton(
              onPressed: () => ref.invalidate(themeChoicesProvider),
              child: const Text('Try again'),
            ),
          ),
          data: _content,
        ),
      ),
      actions: [
        TextButton(
          key: const Key('themes-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('themes-done'),
          onPressed: () => Navigator.of(context).pop(_picked.values.toList()),
          child: const Text('Done'),
        ),
      ],
    );
  }

  Widget _content(ThemeChoices c) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final actions = Wrap(
      spacing: Space.sm,
      runSpacing: Space.xs,
      children: [
        OutlinedButton.icon(
          key: const Key('picker-label-theme'),
          onPressed: _busy ? null : _label,
          icon: const Icon(Icons.label_outline, size: 18),
          label: const Text('Label a project as theme'),
        ),
        OutlinedButton.icon(
          key: const Key('picker-create-theme'),
          onPressed: _busy ? null : () => _create(c),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Create a theme'),
        ),
      ],
    );
    // A theme just created or labelled may not be in the list until the
    // reload ends; show it from the selection meanwhile.
    final listed = {for (final t in c.themes) t.projectId: t};
    for (final t in _picked.values) {
      listed.putIfAbsent(t.projectId, () => t);
    }
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AnnualTermHint(AnnualTerm.themeProject),
          if (listed.isEmpty)
            const EmptyState(
              messageKey: Key('themes-empty'),
              message: 'No theme yet. Label a project or create a theme.',
              icon: Icons.account_tree_outlined,
            )
          else
            for (final t in listed.values)
              _ThemeRow(
                theme: t,
                picked: _picked.containsKey(t.projectId),
                onTap: () => _toggle(t),
              ),
          if (c.unsortedCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Text(
                '${c.unsortedCount} ${c.unsortedCount == 1 ? 'project is' : 'projects are'} '
                'unsorted. Unsorted projects can be classified first.',
                key: const Key('unsorted-note'),
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          const SizedBox(height: Space.md),
          actions,
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Text(_error!,
                  key: const Key('themes-error'),
                  style: TextStyle(color: scheme.error)),
            ),
        ],
      ),
    );
  }
}

class _ThemeRow extends StatelessWidget {
  const _ThemeRow(
      {required this.theme, required this.picked, required this.onTap});

  final ThemeOption theme;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final serves = theme.keyResultIds.length;
    return InkWell(
      key: Key('theme-option-${theme.projectId}'),
      borderRadius: BorderRadius.circular(Corner.md),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.xs),
        child: Row(
          children: [
            Checkbox(value: picked, onChanged: (_) => onTap()),
            const SizedBox(width: Space.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(theme.name, style: text.bodyMedium),
                  if (theme.connectionName.isNotEmpty || serves > 0)
                    Text(
                      [
                        if (theme.connectionName.isNotEmpty)
                          theme.connectionName,
                        if (serves > 0)
                          'serves $serves key ${serves == 1 ? 'result' : 'results'}',
                      ].join(' · '),
                      style: text.bodySmall,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LabelDialog extends StatelessWidget {
  const _LabelDialog({required this.options});

  final List<(String, ClassifiedProject)> options;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      key: const Key('label-dialog'),
      title: const Text('Label a project as theme'),
      content: SizedBox(
        width: 440,
        child: options.isEmpty
            ? const EmptyState(message: 'No project can be labelled.')
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (connection, p) in options)
                      InkWell(
                        key: Key('label-option-${p.id}'),
                        borderRadius: BorderRadius.circular(Corner.md),
                        onTap: () => Navigator.of(context).pop(p),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: Space.sm, horizontal: Space.sm),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.name, style: text.bodyMedium),
                              Text(
                                  '$connection · '
                                  '${p.label == null ? 'unsorted' : 'now ${p.label!.title.toLowerCase()}'}',
                                  style: text.bodySmall),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
