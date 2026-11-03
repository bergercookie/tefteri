/// The right column of the planner: a week time grid with drop targets.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/context_filter.dart';
import '../../core/planning_models.dart';
import '../calendar/calendar_providers.dart';
import 'details_dialogs.dart';
import 'planner_draggable.dart';
import 'planner_providers.dart';
import 'time_grid.dart';

const double _gutterWidth = 44;
const double _minBlockHeight = 22;
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// A week of events and task blocks.
///
/// Drop a task on a day column to plan it: the block starts at the slot under
/// the pointer and the server stores the due date one hour later. Drop it on
/// the all-day row to plan the date only. Task blocks can be dragged again to
/// move them, or back to the task column to unschedule them.
class CalendarPane extends ConsumerStatefulWidget {
  /// Creates the pane for the week that starts on [weekStart] (a Monday).
  const CalendarPane({
    required this.weekStart,
    required this.onShiftWeek,
    required this.onToday,
    this.clock = DateTime.now,
    super.key,
  });

  /// First day of the shown week.
  final DateTime weekStart;

  /// Called with -1 or 1 to move by one week.
  final void Function(int weeks) onShiftWeek;

  /// Called when the user asks for the current week.
  final VoidCallback onToday;

  /// Gives the current time. Tests replace it.
  final DateTime Function() clock;

  @override
  ConsumerState<CalendarPane> createState() => _CalendarPaneState();
}

class _CalendarPaneState extends ConsumerState<CalendarPane> {
  late final ScrollController _scroll;
  Timer? _tick;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = widget.clock();
    // Show the current time when this week holds today, else the morning.
    final today = _days.any((d) => _sameDay(d, _now));
    final minutes = today
        ? (_now.hour * 60 + _now.minute - 2 * 60).clamp(0, minutesPerDay)
        : 7 * 60;
    _scroll = ScrollController(initialScrollOffset: minutesToOffset(minutes));
    // The line moves once a minute.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = widget.clock());
    });
  }

  /// Shows the week of today and scrolls the grid to the current time.
  void _goToToday() {
    widget.onToday();
    setState(() => _now = widget.clock());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final minutes =
          (_now.hour * 60 + _now.minute - 2 * 60).clamp(0, minutesPerDay);
      _scroll.animateTo(
        minutesToOffset(minutes).clamp(0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<DateTime> get _days => [
        for (var i = 0; i < calendarDays; i++)
          DateTime(widget.weekStart.year, widget.weekStart.month,
              widget.weekStart.day + i),
      ];

  @override
  Widget build(BuildContext context) {
    ref.watch(contextFilterProvider);
    final items = ref.watch(calendarItemsProvider(widget.weekStart));
    final pending = ref.watch(pendingTaskProvider);
    return Column(
      key: const Key('calendar-pane'),
      children: [
        _nav(),
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
                    onPressed: () => ref.read(plannerActionsProvider).refresh(),
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
            data: (list) => _grid(list, pending),
          ),
        ),
      ],
    );
  }

  /// Today button, arrows and the label of the week. On a narrow screen the
  /// label can shrink, so the row never overflows.
  Widget _nav() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            OutlinedButton(
              key: const Key('today-button'),
              onPressed: _goToToday,
              child: const Text('Today'),
            ),
            IconButton(
              key: const Key('prev-week'),
              tooltip: 'Previous week (Left arrow)',
              icon: const Icon(Icons.chevron_left),
              onPressed: () => widget.onShiftWeek(-1),
            ),
            IconButton(
              key: const Key('next-week'),
              tooltip: 'Next week (Right arrow)',
              icon: const Icon(Icons.chevron_right),
              onPressed: () => widget.onShiftWeek(1),
            ),
            Expanded(
              child: Text(
                'Week of ${dateKey(widget.weekStart)}',
                key: const Key('week-label'),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );

  Widget _grid(List<CalendarItem> all, String? pending) {
    final days = _days;
    return Column(
      children: [
        Row(
          children: [
            const SizedBox(width: _gutterWidth),
            for (final d in days)
              Expanded(
                child: Center(
                  child: Text('${_weekdays[d.weekday - 1]} ${d.day}',
                      style: Theme.of(context).textTheme.labelMedium),
                ),
              ),
          ],
        ),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: _gutterWidth,
                child: Center(
                    child: Text('all day',
                        style: Theme.of(context).textTheme.labelSmall)),
              ),
              for (final d in days)
                Expanded(
                    child: _allDayCell(
                        d, _itemsOnDay(all, d, allDay: true), pending)),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            key: const Key('time-grid'),
            controller: _scroll,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: _gutterWidth,
                  child: Column(
                    children: [
                      for (var h = 0; h < 24; h++)
                        SizedBox(
                          height: hourHeight,
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: Text('${h.toString().padLeft(2, '0')}:00',
                                style: Theme.of(context).textTheme.labelSmall),
                          ),
                        ),
                    ],
                  ),
                ),
                for (final d in days)
                  Expanded(
                      child: _DayColumn(
                    day: d,
                    items: _itemsOnDay(all, d, allDay: false),
                    pending: pending,
                    now: _sameDay(d, _now) ? _now : null,
                  )),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Items that touch [day] (local time), either all-day or timed.
  List<CalendarItem> _itemsOnDay(List<CalendarItem> all, DateTime day,
      {required bool allDay}) {
    final from = day;
    final to = DateTime(day.year, day.month, day.day + 1);
    return [
      for (final i in all)
        if (i.allDay == allDay &&
            i.start != null &&
            i.start!.toLocal().isBefore(to) &&
            (i.end ?? i.start!).toLocal().isAfter(from))
          i,
    ];
  }

  Widget _allDayCell(DateTime day, List<CalendarItem> items, String? pending) {
    return DragTarget<Object>(
      key: Key('allday-${dateKey(day)}'),
      onWillAcceptWithDetails: (d) => _taskIdOf(d.data) != null,
      onAcceptWithDetails: (d) {
        final id = _taskIdOf(d.data);
        if (id == null) return;
        ref.read(plannerActionsProvider).scheduleOnDate(id, day);
      },
      builder: (context, candidates, _) => Container(
        constraints: const BoxConstraints(minHeight: 28),
        margin: const EdgeInsets.all(1),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: candidates.isEmpty
              ? null
              : Theme.of(context).colorScheme.primaryContainer,
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final i in items)
              _AllDayChip(item: i, pending: pending == i.id),
          ],
        ),
      ),
    );
  }
}

/// Task id carried by a dragged task row or task block; null for others.
String? _taskIdOf(Object data) {
  if (data is PlanTask) return data.id;
  if (data is CalendarItem && data.isTask) return data.id;
  return null;
}

Color _blockColor(BuildContext context, CalendarItem i) {
  final scheme = Theme.of(context).colorScheme;
  return i.isTask ? scheme.tertiaryContainer : scheme.primaryContainer;
}

class _AllDayChip extends StatelessWidget {
  const _AllDayChip({required this.item, required this.pending});

  final CalendarItem item;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final chip = _OpenDetails(
        item: item,
        child: Container(
          key: Key('allday-${item.type}-${item.id}'),
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          color: _blockColor(context, item),
          child: Row(
            children: [
              Icon(item.isTask ? Icons.task_alt : Icons.event, size: 12),
              const SizedBox(width: 2),
              Expanded(
                child: Text(item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        decoration:
                            item.isDone ? TextDecoration.lineThrough : null)),
              ),
            ],
          ),
        ));
    if (!item.isTask) return chip;
    return PlannerDraggable<CalendarItem>(
        data: item, label: item.title, dimmed: pending, child: chip);
  }
}

class _DayColumn extends ConsumerWidget {
  const _DayColumn({
    required this.day,
    required this.items,
    required this.pending,
    required this.now,
  });

  final DateTime day;
  final List<CalendarItem> items;
  final String? pending;

  /// The current time when [day] is today; null on other days.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boxKey = GlobalKey();
    final dayStart = day;
    final dayEnd = DateTime(day.year, day.month, day.day + 1);
    // Minutes after midnight of the part of each item that lies on this day.
    final spans = <(int, int)>[
      for (final i in items)
        (
          _minutes(i.start!.toLocal(), dayStart, dayEnd, start: true),
          _minutes((i.end ?? i.start!.add(const Duration(hours: 1))).toLocal(),
              dayStart, dayEnd,
              start: false),
        ),
    ];
    final layout = layoutOverlaps(spans);
    return DragTarget<Object>(
      onWillAcceptWithDetails: (d) => _taskIdOf(d.data) != null,
      onAcceptWithDetails: (d) {
        final id = _taskIdOf(d.data);
        final box = boxKey.currentContext?.findRenderObject() as RenderBox?;
        if (id == null || box == null) return;
        final local = box.globalToLocal(d.offset);
        ref
            .read(plannerActionsProvider)
            .scheduleAt(id, slotStart(day, local.dy));
      },
      builder: (context, candidates, _) => Container(
        key: boxKey,
        height: hourHeight * 24,
        decoration: BoxDecoration(
          color: candidates.isEmpty
              ? null
              : Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withValues(alpha: 0.3),
          border:
              Border(left: BorderSide(color: Theme.of(context).dividerColor)),
        ),
        child: LayoutBuilder(
          builder: (context, c) => Stack(
            key: Key('day-column-${dateKey(day)}'),
            clipBehavior: Clip.hardEdge,
            children: [
              for (var h = 1; h < 24; h++)
                Positioned(
                  top: h * hourHeight,
                  left: 0,
                  right: 0,
                  child:
                      Divider(height: 1, color: Theme.of(context).dividerColor),
                ),
              for (var n = 0; n < items.length; n++)
                _block(context, items[n], spans[n], layout[n], c.maxWidth),
              if (now != null) _nowLine(now!),
            ],
          ),
        ),
      ),
    );
  }

  /// The red dot and line at the current time, as in Google Calendar. It does
  /// not take pointer events, so a drop still reaches the column.
  Widget _nowLine(DateTime now) {
    const dot = 10.0;
    const color = Color(0xFFD93025);
    return Positioned(
      key: const Key('now-indicator'),
      top: minutesToOffset(now.hour * 60 + now.minute) - dot / 2,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Row(
          children: [
            Container(
              width: dot,
              height: dot,
              decoration:
                  const BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const Expanded(
                child: SizedBox(height: 2, child: ColoredBox(color: color))),
          ],
        ),
      ),
    );
  }

  int _minutes(DateTime t, DateTime dayStart, DateTime dayEnd,
      {required bool start}) {
    if (start && t.isBefore(dayStart)) return 0;
    if (!start && t.isAfter(dayEnd)) return minutesPerDay;
    return t.difference(dayStart).inMinutes;
  }

  Widget _block(BuildContext context, CalendarItem i, (int, int) span,
      BlockColumn place, double width) {
    final colWidth = width / place.columns;
    final height = (minutesToOffset(span.$2 - span.$1))
        .clamp(_minBlockHeight, double.infinity);
    final time =
        '${hhmm(i.start!)}${i.end == null ? '' : ' - ${hhmm(i.end!)}'}';
    final isPending = pending == i.id;
    final body = _OpenDetails(
        item: i,
        child: Container(
          key: Key('block-${i.type}-${i.id}'),
          margin: const EdgeInsets.all(1),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: _blockColor(context, i),
            borderRadius: BorderRadius.circular(4),
            border: i.isTask
                ? Border.all(color: Theme.of(context).colorScheme.tertiary)
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(i.isTask ? Icons.task_alt : Icons.event, size: 12),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Text(i.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            decoration:
                                i.isDone ? TextDecoration.lineThrough : null)),
                  ),
                  if (i.clippedStart)
                    Tooltip(
                      message: 'Continues from previous day',
                      child: Icon(Icons.subdirectory_arrow_right,
                          key: Key('clipped-${i.id}'), size: 12),
                    ),
                ],
              ),
              if (height >= 40)
                Text(time,
                    maxLines: 1, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ));
    return Positioned(
      top: minutesToOffset(span.$1),
      left: colWidth * place.column,
      width: colWidth,
      height: height,
      child: i.isTask
          ? PlannerDraggable<CalendarItem>(
              data: i, label: i.title, dimmed: isPending, child: body)
          : body,
    );
  }
}

/// Opens the details pop-up of [item] when the user taps [child]: the task for
/// a task block, the event for an event.
class _OpenDetails extends StatelessWidget {
  const _OpenDetails({required this.item, required this.child});

  final CalendarItem item;
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => item.isTask
            ? showTaskDetails(context, taskId: item.id, title: item.title)
            : showEventDetails(context, item),
        child: child,
      );
}
