/// The planning checklist of a week, month or year, to tick while planning.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_error.dart';
import '../../core/planning_models.dart';
import '../../theme/theme.dart';
import 'checklist_controller.dart';

/// Where the user writes their checklists.
const String checklistSettingsPath = '/settings/checklists';

/// The checklist for the period that holds [day].
///
/// With items, they can be ticked; the ticks belong to the period, so the next
/// week, month or year starts clean. Without items, it says that a checklist
/// can be made and opens the settings for it.
///
/// [card] draws a frame around it, for a page of its own; [collapsible] folds
/// the items away behind a line with the count, for a narrow screen.
class PlanningChecklist extends ConsumerStatefulWidget {
  /// Creates the checklist of [kind] for the period that holds [day].
  const PlanningChecklist({
    required this.kind,
    required this.day,
    this.card = false,
    this.collapsible = false,
    super.key,
  });

  /// The kind of planning.
  final ChecklistKind kind;

  /// A day in the week, month or year.
  final DateTime day;

  /// Draw a frame.
  final bool card;

  /// Fold the items away until the user opens them.
  final bool collapsible;

  @override
  ConsumerState<PlanningChecklist> createState() => _PlanningChecklistState();
}

class _PlanningChecklistState extends ConsumerState<PlanningChecklist> {
  bool _open = false;

  ChecklistKey get _key =>
      (kind: widget.kind, day: _dayKey(widget.day, widget.kind));

  /// The first day of the period, so that every day of it shares one provider.
  static String _dayKey(DateTime d, ChecklistKind kind) {
    final first = switch (kind) {
      ChecklistKind.week => DateTime(d.year, d.month, d.day - (d.weekday - 1)),
      ChecklistKind.month => DateTime(d.year, d.month, 1),
      ChecklistKind.year => DateTime(d.year, 1, 1),
    };
    return dateKey(first);
  }

  Future<void> _tick(String text, bool checked) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final error =
        await ref.read(checklistProvider(_key).notifier).tick(text, checked);
    if (error != null) {
      messenger?.showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(checklistProvider(_key));
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final title = '${widget.kind.adjective} checklist';
    final list = state.valueOrNull;

    final String summary;
    if (list == null) {
      summary = state.hasError ? 'Could not load it' : 'Loading';
    } else if (list.items.isEmpty) {
      summary = 'Not set up yet';
    } else if (list.done == list.items.length) {
      summary =
          list.items.length == 1 ? 'Done' : 'All ${list.items.length} done';
    } else {
      summary = '${list.done} of ${list.items.length} done';
    }

    final header = Row(
      children: [
        Expanded(child: Text(title, style: text.titleMedium)),
        Text(summary,
            key: const Key('checklist-summary'),
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        if (widget.collapsible) ...[
          const SizedBox(width: Space.xs),
          Icon(_open ? Icons.expand_less : Icons.expand_more,
              color: scheme.onSurfaceVariant),
        ],
      ],
    );

    final Widget body = state.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: Space.md),
        child: Loading(),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.only(top: Space.sm),
        child: Row(
          children: [
            Expanded(
              child: Text(apiErrorMessage(e),
                  key: const Key('checklist-error'), style: text.bodySmall),
            ),
            TextButton(
              key: const Key('checklist-retry'),
              onPressed: () =>
                  ref.read(checklistProvider(_key).notifier).load(),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
      data: (c) => c.items.isEmpty ? _hint(context) : _items(context, c),
    );

    final content = widget.collapsible
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                key: const Key('checklist-toggle'),
                borderRadius: BorderRadius.circular(Corner.md),
                onTap: () => setState(() => _open = !_open),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.sm),
                  child: header,
                ),
              ),
              if (_open) body,
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [header, body],
          );

    if (!widget.card) {
      return KeyedSubtree(
          key: Key('planning-checklist-${widget.kind.name}'), child: content);
    }
    return Container(
      key: Key('planning-checklist-${widget.kind.name}'),
      margin: const EdgeInsets.only(bottom: Space.sm),
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        border: Border.all(color: context.tefteri.rule),
        borderRadius: BorderRadius.circular(Corner.lg),
      ),
      child: content,
    );
  }

  /// What to show when there is no list yet: why it helps and a way to make one.
  Widget _hint(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final kind = widget.kind;
    return Padding(
      padding: const EdgeInsets.only(top: Space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'You have no ${kind.adjective.toLowerCase()} checklist yet. '
            'List what you want to go through every ${kind.noun}, and tick it '
            'off here while you plan. It starts clean each ${kind.noun}.',
            key: const Key('checklist-hint'),
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: Space.sm),
          OutlinedButton.icon(
            key: const Key('checklist-create'),
            icon: const Icon(Icons.checklist),
            label: const Text('Create a checklist'),
            onPressed: () => context.go(checklistSettingsPath),
          ),
        ],
      ),
    );
  }

  Widget _items(BuildContext context, PeriodChecklist list) {
    final colors = context.tefteri;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final all = list.done == list.items.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Space.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(Corner.pill),
          child: LinearProgressIndicator(
            key: const Key('checklist-bar'),
            value: list.done / list.items.length,
            minHeight: 4,
            color: colors.done,
            backgroundColor: colors.rule,
          ),
        ),
        const SizedBox(height: Space.xs),
        for (var i = 0; i < list.items.length; i++)
          Container(
            decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: colors.rule))),
            child: InkWell(
              key: Key('checklist-item-$i'),
              onTap: () => _tick(list.items[i].text, !list.items[i].checked),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ExcludeFocus(
                      child: Checkbox(
                        key: Key('checklist-box-$i'),
                        value: list.items[i].checked,
                        activeColor: colors.done,
                        visualDensity: VisualDensity.compact,
                        onChanged: (v) => _tick(list.items[i].text, v ?? false),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: Space.sm),
                        child: Text(
                          list.items[i].text,
                          style: text.bodyMedium?.copyWith(
                            color: list.items[i].checked
                                ? scheme.onSurfaceVariant
                                : null,
                            decoration: list.items[i].checked
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (all)
          Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_circle, size: 18, color: colors.done),
                const SizedBox(width: Space.xs),
                Expanded(
                  child: Text('Everything on the list is done.',
                      key: const Key('checklist-all-done'),
                      style: text.bodySmall),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            key: const Key('checklist-edit'),
            onPressed: () => context.go(checklistSettingsPath),
            child: const Text('Edit the list'),
          ),
        ),
      ],
    );
  }
}
