/// The dialog that chooses what the planner shows.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/calendar_color.dart';
import '../../theme/theme.dart';
import '../settings/calendar_choice.dart';
import '../settings/connection_dialog.dart';
import '../settings/connection_models.dart';
import '../settings/sync_controller.dart';
import 'planner_visibility.dart';

/// Opens the dialog that shows or hides the planner panes and their sources.
Future<void> showPlannerViewsDialog(BuildContext context) => showDialog<void>(
      context: context,
      builder: (_) => const PlannerViewsDialog(),
    );

/// Switches for the two panes, every task provider and every calendar.
///
/// Hiding a source changes only this view: its data keeps syncing.
class PlannerViewsDialog extends ConsumerWidget {
  /// Creates the dialog.
  const PlannerViewsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visibility = ref.watch(plannerVisibilityProvider);
    final connections = ref.watch(connectionsProvider);
    return AlertDialog(
      key: const Key('planner-views-dialog'),
      title: const Text('What the planner shows'),
      content: SizedBox(
        width: 440,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.68),
          child: connections.when(
            loading: () => const SizedBox(height: 120, child: Loading()),
            error: (e, _) => EmptyState(
              icon: Icons.link_outlined,
              message: apiErrorMessage(e),
              action: TextButton(
                key: const Key('planner-views-retry'),
                onPressed: () => ref.invalidate(connectionsProvider),
                child: const Text('Try again'),
              ),
            ),
            data: (list) => _body(context, ref, visibility, list),
          ),
        ),
      ),
      actions: [
        if (visibility.hasHiddenSources)
          TextButton(
            key: const Key('planner-views-show-all'),
            onPressed: () =>
                ref.read(plannerVisibilityProvider.notifier).showAllSources(),
            child: const Text('Show all sources'),
          ),
        TextButton(
          key: const Key('planner-views-close'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _body(BuildContext context, WidgetRef ref,
      PlannerVisibility visibility, List<Connection> connections) {
    final taskConnections = [
      for (final c in connections)
        if (c.kind == 'tasks') c,
    ];
    final calendarConnections = [
      for (final c in connections)
        if (c.kind == 'calendar') c,
    ];
    return ListView(
      shrinkWrap: true,
      children: [
        _header(context, 'Views'),
        SwitchListTile(
          key: const Key('planner-show-tasks'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Tasks'),
          subtitle: const Text('The task list on the left.'),
          value: visibility.showTasks,
          // The planner must keep at least one pane.
          onChanged: visibility.showTasks && !visibility.showCalendar
              ? null
              : (v) =>
                  ref.read(plannerVisibilityProvider.notifier).setShowTasks(v),
        ),
        SwitchListTile(
          key: const Key('planner-show-calendar'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Calendar'),
          subtitle: const Text('The week grid on the right.'),
          value: visibility.showCalendar,
          onChanged: visibility.showCalendar && !visibility.showTasks
              ? null
              : (v) => ref
                  .read(plannerVisibilityProvider.notifier)
                  .setShowCalendar(v),
        ),
        const SizedBox(height: Space.sm),
        _header(
          context,
          'Task providers',
          action: taskConnections.isEmpty
              ? null
              : _ShowAllButton(
                  key: const Key('planner-task-sources-toggle'),
                  allShown: taskConnections
                      .every((c) => visibility.showsTaskConnection(c.id)),
                  what: 'tasks of every task app',
                  onChanged: (v) => ref
                      .read(plannerVisibilityProvider.notifier)
                      .setTaskConnectionsVisible(
                          [for (final c in taskConnections) c.id], v),
                ),
        ),
        if (taskConnections.isEmpty)
          _empty(context, 'No task apps are connected.')
        else
          for (final connection in taskConnections)
            SwitchListTile(
              key: Key('planner-task-source-${connection.id}'),
              contentPadding: EdgeInsets.zero,
              title: Text(connection.displayName),
              subtitle: Text(
                  ConnectionProvider.byId(connection.provider)?.label ??
                      connection.provider),
              value: visibility.showsTaskConnection(connection.id),
              onChanged: (v) => ref
                  .read(plannerVisibilityProvider.notifier)
                  .setTaskConnectionVisible(connection.id, v),
            ),
        const SizedBox(height: Space.sm),
        _header(context, 'Calendars'),
        if (calendarConnections.isEmpty)
          _empty(context, 'No calendar apps are connected.')
        else
          for (final connection in calendarConnections)
            _CalendarGroup(connection: connection, visibility: visibility),
      ],
    );
  }

  Widget _header(BuildContext context, String text, {Widget? action}) =>
      Padding(
        padding: const EdgeInsets.only(top: Space.sm, bottom: Space.xs),
        child: Row(
          children: [
            Expanded(
                child:
                    Text(text, style: Theme.of(context).textTheme.titleSmall)),
            if (action != null) action,
          ],
        ),
      );

  Widget _empty(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: Space.sm),
        child: Text(text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}

class _CalendarGroup extends ConsumerWidget {
  const _CalendarGroup({required this.connection, required this.visibility});

  final Connection connection;
  final PlannerVisibility visibility;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final calendars = ref.watch(calendarsProvider(connection.id));
    return calendars.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: Space.sm),
        child: LinearProgressIndicator(),
      ),
      error: (e, _) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(apiErrorMessage(e)),
        subtitle: Text(connection.displayName),
        trailing: TextButton(
          key: Key('planner-calendar-retry-${connection.id}'),
          onPressed: () => ref.invalidate(calendarsProvider(connection.id)),
          child: const Text('Try again'),
        ),
      ),
      data: (list) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // One switch for all the calendars of this connection.
          if (list.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      connection.displayName,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                  _ShowAllButton(
                    key: Key('planner-calendar-group-toggle-${connection.id}'),
                    allShown: list.every((c) => visibility.showsCalendar(c.id)),
                    what: 'calendars of ${connection.displayName}',
                    onChanged: (v) => ref
                        .read(plannerVisibilityProvider.notifier)
                        .setCalendarsVisible([for (final c in list) c.id], v),
                  ),
                ],
              ),
            ),
          for (final calendar in list)
            _CalendarSwitch(
              connection: connection,
              calendar: calendar,
              visibility: visibility,
            ),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: Text('${connection.displayName} has no calendars.',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}

class _CalendarSwitch extends ConsumerWidget {
  const _CalendarSwitch({
    required this.connection,
    required this.calendar,
    required this.visibility,
  });

  final Connection connection;
  final CalendarInfo calendar;
  final PlannerVisibility visibility;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final notes = [
      if (calendar.readOnly) 'Read only',
      if (!calendar.enabled) 'Sync is off',
    ];
    return SwitchListTile(
      key: Key('planner-calendar-source-${calendar.id}'),
      contentPadding: EdgeInsets.zero,
      title: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: parseCalendarColor(calendar.color) ?? muted,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: Space.sm),
          Expanded(child: Text(calendar.name)),
        ],
      ),
      subtitle: notes.isEmpty
          ? Text(connection.displayName)
          : Text('${notes.join(' - ')} - ${connection.displayName}'),
      value: visibility.showsCalendar(calendar.id),
      onChanged: (v) => ref
          .read(plannerVisibilityProvider.notifier)
          .setCalendarVisible(calendar.id, v),
    );
  }
}

/// "Hide all" while every source of a group is shown, else "Show all".
class _ShowAllButton extends StatelessWidget {
  const _ShowAllButton({
    required this.allShown,
    required this.what,
    required this.onChanged,
    super.key,
  });

  /// True when every source of the group is shown.
  final bool allShown;

  /// The sources of the group, for the tooltip ("calendars of Work").
  final String what;

  /// Called with true to show every source of the group, false to hide them.
  final void Function(bool visible) onChanged;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: '${allShown ? 'Hide' : 'Show'} the $what',
        child: TextButton.icon(
          onPressed: () => onChanged(!allShown),
          icon: Icon(
              allShown
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 18),
          label: Text(allShown ? 'Hide all' : 'Show all'),
          style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        ),
      );
}
