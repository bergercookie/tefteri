/// The right column of the planner: a week time grid with drop targets.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/context_filter.dart';
import '../../core/planning_models.dart';
import '../calendar/calendar_providers.dart';
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
    super.key,
  });

  /// First day of the shown week.
  final DateTime weekStart;

  /// Called with -1 or 1 to move by one week.
  final void Function(int weeks) onShiftWeek;

  /// Called when the user asks for the current week.
  final VoidCallback onToday;

  @override
  ConsumerState<CalendarPane> createState() => _CalendarPaneState();
}

class _CalendarPaneState extends ConsumerState<CalendarPane> {
  final _scroll =
      ScrollController(initialScrollOffset: minutesToOffset(7 * 60));

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

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

  Widget _nav() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            key: const Key('prev-week'),
            tooltip: 'Previous week',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => widget.onShiftWeek(-1),
          ),
          TextButton(
            key: const Key('this-week'),
            onPressed: widget.onToday,
            child: Text('Week of ${dateKey(widget.weekStart)}'),
          ),
          IconButton(
            key: const Key('next-week'),
            tooltip: 'Next week',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => widget.onShiftWeek(1),
          ),
        ],
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
    final chip = Container(
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
    );
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
  });

  final DateTime day;
  final List<CalendarItem> items;
  final String? pending;

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
            ],
          ),
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
    final body = Container(
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
    );
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
