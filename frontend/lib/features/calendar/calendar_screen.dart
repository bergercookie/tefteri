/// Calendar view: a week of entries and scheduled tasks.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/context_filter.dart';
import '../../core/planning_api.dart';
import '../../core/planning_models.dart';
import '../../core/shell.dart';
import 'calendar_providers.dart';

/// Hour used when a task is dropped on a day.
const defaultScheduleHour = 9;

/// Shows one week. Long-press a task and drop it on a day, or tap it to
/// choose a day and time. Scheduling never creates a calendar event.
class CalendarScreen extends ConsumerStatefulWidget {
  /// Creates the screen; the week contains [initialDate] (default today).
  const CalendarScreen({this.initialDate, super.key});

  /// A day in the week to show first.
  final DateTime? initialDate;

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _weekStart;
  String? _error;

  @override
  void initState() {
    super.initState();
    final d = widget.initialDate ?? DateTime.now();
    _weekStart = DateTime(d.year, d.month, d.day - (d.weekday - 1));
  }

  List<DateTime> get _days => [
        for (var i = 0; i < calendarDays; i++)
          DateTime(_weekStart.year, _weekStart.month, _weekStart.day + i),
      ];

  void _shiftWeek(int weeks) => setState(() {
        _weekStart = DateTime(
            _weekStart.year, _weekStart.month, _weekStart.day + 7 * weeks);
        _error = null;
      });

  void _reload() {
    ref.invalidate(calendarItemsProvider(_weekStart));
    ref.invalidate(unscheduledTasksProvider);
  }

  /// Runs a write action. Failures show the server message and are not queued.
  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on DioException catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
      return;
    }
    if (!mounted) return;
    setState(() => _error = null);
    _reload();
  }

  Future<void> _schedule(String taskId, DateTime start) => _run(() => ref
      .read(planningApiProvider)
      .scheduleTask(taskId, start, start.add(const Duration(hours: 1))));

  Future<void> _choose(String taskId, DateTime initial) async {
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (_) => ScheduleDialog(days: _days, initial: initial),
    );
    if (picked != null) await _schedule(taskId, picked);
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(calendarItemsProvider(_weekStart));
    final unscheduled = ref.watch(unscheduledTasksProvider);
    return AppShell(
      title: 'Calendar',
      body: Column(
        children: [
          if (_error != null)
            ErrorBanner(
                message: _error!,
                onDismiss: () => setState(() => _error = null)),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                key: const Key('prev-week'),
                tooltip: 'Previous week',
                icon: const Icon(Icons.chevron_left),
                onPressed: () => _shiftWeek(-1),
              ),
              Text('Week of ${dateKey(_weekStart)}'),
              IconButton(
                key: const Key('next-week'),
                tooltip: 'Next week',
                icon: const Icon(Icons.chevron_right),
                onPressed: () => _shiftWeek(1),
              ),
            ],
          ),
          Expanded(
            child: items.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(apiErrorMessage(e), key: const Key('load-error')),
                    TextButton(
                      key: const Key('reload-button'),
                      onPressed: _reload,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
              data: (list) => SingleChildScrollView(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _unscheduledSection(unscheduled.valueOrNull ?? const []),
                    for (final day in _days) _dayTarget(day, list),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _unscheduledSection(List<PlanTask> tasks) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Not scheduled', style: Theme.of(context).textTheme.titleMedium),
        if (tasks.isEmpty) const Text('All tasks have a time.'),
        Wrap(
          spacing: 8,
          children: [
            for (final t in tasks)
              LongPressDraggable<PlanTask>(
                data: t,
                feedback: Material(child: Chip(label: Text(t.title))),
                child: ActionChip(
                  key: Key('unscheduled-${t.id}'),
                  avatar: const Icon(Icons.task_alt, size: 16),
                  label: Text(t.title),
                  onPressed: () => _choose(
                    t.id,
                    DateTime(_weekStart.year, _weekStart.month, _weekStart.day,
                        defaultScheduleHour),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _dayTarget(DateTime day, List<CalendarItem> all) {
    final mine = all.where((i) {
      final s = i.start?.toLocal();
      return s != null &&
          s.year == day.year &&
          s.month == day.month &&
          s.day == day.day;
    }).toList()
      ..sort((a, b) => a.start!.compareTo(b.start!));
    return DragTarget<PlanTask>(
      key: Key('day-${dateKey(day)}'),
      onAcceptWithDetails: (d) => _schedule(d.data.id,
          DateTime(day.year, day.month, day.day, defaultScheduleHour)),
      builder: (context, candidates, _) => Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(
            color: candidates.isEmpty
                ? Theme.of(context).dividerColor
                : Theme.of(context).colorScheme.primary,
            width: candidates.isEmpty ? 1 : 2,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(dateKey(day), style: Theme.of(context).textTheme.titleSmall),
            if (mine.isEmpty) const Text('Nothing planned.'),
            for (final i in mine) _itemCard(i),
          ],
        ),
      ),
    );
  }

  Widget _itemCard(CalendarItem i) {
    final scheme = Theme.of(context).colorScheme;
    final time = i.allDay || i.start == null
        ? 'All day'
        : '${hhmm(i.start!)}${i.end == null ? '' : ' - ${hhmm(i.end!)}'}';
    return Card(
      key: Key('${i.type}-item-${i.id}'),
      color: i.isTask ? scheme.tertiaryContainer : scheme.primaryContainer,
      child: ListTile(
        dense: true,
        leading: Icon(i.isTask ? Icons.task_alt : Icons.event),
        title: Text(i.title),
        subtitle: Text('${i.isTask ? 'Task' : 'Event'} - $time'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ContextMarker(itemContext: i.context),
            if (i.isTask)
              PopupMenuButton<String>(
                key: Key('task-menu-${i.id}'),
                onSelected: (v) {
                  if (v == 'change') {
                    _choose(i.id, i.start ?? _weekStart);
                  } else {
                    _run(() =>
                        ref.read(planningApiProvider).unscheduleTask(i.id));
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'change', child: Text('Change time')),
                  PopupMenuItem(value: 'remove', child: Text('Unschedule')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Dialog to choose a day and an hour for a task.
class ScheduleDialog extends StatefulWidget {
  /// Creates a dialog that offers [days] and starts at [initial].
  const ScheduleDialog({required this.days, required this.initial, super.key});

  /// Days the user can choose.
  final List<DateTime> days;

  /// Initial day and hour.
  final DateTime initial;

  @override
  State<ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends State<ScheduleDialog> {
  late DateTime _day;
  late int _hour;

  @override
  void initState() {
    super.initState();
    final i = widget.initial.toLocal();
    _day = widget.days.firstWhere(
        (d) => d.year == i.year && d.month == i.month && d.day == i.day,
        orElse: () => widget.days.first);
    _hour = i.hour;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Choose a time'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButton<DateTime>(
            key: const Key('schedule-day'),
            value: _day,
            items: [
              for (final d in widget.days)
                DropdownMenuItem(value: d, child: Text(dateKey(d))),
            ],
            onChanged: (v) => setState(() => _day = v ?? _day),
          ),
          DropdownButton<int>(
            key: const Key('schedule-hour'),
            value: _hour,
            items: [
              for (var h = 0; h < 24; h++)
                DropdownMenuItem(
                    value: h,
                    child: Text('${h.toString().padLeft(2, '0')}:00')),
            ],
            onChanged: (v) => setState(() => _hour = v ?? _hour),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('schedule-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('schedule-confirm'),
          onPressed: () => Navigator.of(context)
              .pop(DateTime(_day.year, _day.month, _day.day, _hour)),
          child: const Text('Schedule'),
        ),
      ],
    );
  }
}
