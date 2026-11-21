/// The right column of the planner: a week time grid with drop targets.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/browser_menu.dart';
import '../../core/calendar_color.dart';
import '../../core/control_key.dart';
import '../../core/event_input.dart';
import '../../core/planning_models.dart';
import '../../theme/theme.dart';
import '../calendar/calendar_providers.dart';
import 'details_dialogs.dart';
import 'new_event_dialog.dart';
import 'planner_draggable.dart';
import 'planner_providers.dart';
import 'planner_span.dart';
import 'planner_visibility.dart';
import 'shared_events.dart';
import 'time_grid.dart';

const double _gutterWidth = 44;
const double _minBlockHeight = 22;
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// A week, three days or one day of events and task blocks.
///
/// Drop a task on a day column to plan it: the block starts at the slot under
/// the pointer and the server stores the due date one hour later. Drop it on
/// the all-day row to plan the date only. Task blocks can be dragged again to
/// move them, or back to the task column to unschedule them.
class CalendarPane extends ConsumerStatefulWidget {
  /// Creates the pane for the [span] of days that starts on [start].
  const CalendarPane({
    required this.start,
    required this.onShift,
    required this.onToday,
    this.span = PlannerSpan.week,
    this.onSpan,
    this.clock = DateTime.now,
    super.key,
  });

  /// First day shown: a Monday in the week view.
  final DateTime start;

  /// How many days the pane shows.
  final PlannerSpan span;

  /// Called with -1 or 1 to move by one [span].
  final void Function(int steps) onShift;

  /// Called when the user asks for today.
  final VoidCallback onToday;

  /// Called when the user chooses another span. Without it there is no menu.
  final ValueChanged<PlannerSpan>? onSpan;

  /// Gives the current time. Tests replace it.
  final DateTime Function() clock;

  @override
  ConsumerState<CalendarPane> createState() => _CalendarPaneState();
}

class _CalendarPaneState extends ConsumerState<CalendarPane> {
  late final ScrollController _scroll;
  final _gridKey = GlobalKey();
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

  /// Shows today and scrolls the grid to the current time.
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

  /// Scrolls the grid while a task is dragged near its top or bottom edge, so
  /// that every hour can be reached without letting go.
  void _autoScroll(Offset pointer) {
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !_scroll.hasClients) return;
    final y = box.globalToLocal(pointer).dy;
    const edge = 48.0;
    const step = 14.0;
    final delta = y < edge
        ? -step
        : y > box.size.height - edge
            ? step
            : 0.0;
    if (delta == 0) return;
    _scroll.jumpTo(
        (_scroll.offset + delta).clamp(0.0, _scroll.position.maxScrollExtent));
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
        for (var i = 0; i < widget.span.days; i++)
          DateTime(widget.start.year, widget.start.month, widget.start.day + i),
      ];

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(calendarItemsProvider(widget.start));
    final visibility = ref.watch(plannerVisibilityProvider);
    final pending = ref.watch(pendingTaskProvider);
    return Column(
      key: const Key('calendar-pane'),
      children: [
        _nav(),
        Expanded(
          child: items.when(
            loading: () => const Loading(),
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
            // Copies of one event in two shown calendars show once.
            data: (list) =>
                _grid(mergeSharedEvents(_visible(list, visibility)), pending),
          ),
        ),
      ],
    );
  }

  /// Leaves out the task providers and calendars that the user hid.
  List<CalendarItem> _visible(
          List<CalendarItem> items, PlannerVisibility visibility) =>
      [
        for (final item in items)
          if (item.isTask
              ? visibility.showsTaskConnection(item.connectionId)
              : visibility.showsCalendar(item.containerId))
            item,
      ];

  /// The label of the shown days: "Week of 2026-11-02",
  /// "2026-11-04 to 2026-11-06" or "Wed 2026-11-04".
  String get _label {
    final days = _days;
    return switch (widget.span) {
      PlannerSpan.week => 'Week of ${dateKey(widget.start)}',
      PlannerSpan.threeDays =>
        '${dateKey(days.first)} to ${dateKey(days.last)}',
      PlannerSpan.day =>
        '${_weekdays[widget.start.weekday - 1]} ${dateKey(widget.start)}',
    };
  }

  /// Today button, arrows, the label of the days and the span menu. On a
  /// narrow screen the label can shrink, so the row never overflows.
  Widget _nav() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 4),
        child: LayoutBuilder(
            builder: (context, c) => Row(
                  children: [
                    OutlinedButton(
                      key: const Key('today-button'),
                      onPressed: _goToToday,
                      child: const Text('Today'),
                    ),
                    IconButton(
                      key: const Key('prev-week'),
                      tooltip: 'Previous ${widget.span.unit} (Left arrow)',
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => widget.onShift(-1),
                    ),
                    IconButton(
                      key: const Key('next-week'),
                      tooltip: 'Next ${widget.span.unit} (Right arrow)',
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => widget.onShift(1),
                    ),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Text(
                        _label,
                        key: const Key('week-label'),
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    _newEventButton(compact: c.maxWidth < _labelledNavWidth),
                    if (widget.onSpan != null)
                      _spanMenu(compact: c.maxWidth < _compactNavWidth),
                  ],
                )),
      );

  /// Opens the pop-up that adds an event, at the next full hour. Shift+N does
  /// the same. When [compact], it is an icon.
  Widget _newEventButton({required bool compact}) {
    void open() =>
        showNewEventDialog(context, start: nextFullHour(widget.clock()));
    return Padding(
      padding: const EdgeInsets.only(right: Space.sm),
      child: compact
          ? IconButton.filled(
              key: const Key('new-event-button'),
              tooltip: 'New event (Shift+N)',
              icon: const Icon(Icons.event_available_outlined, size: 18),
              onPressed: open,
            )
          : Tooltip(
              message: 'Shift+N',
              child: FilledButton.icon(
                key: const Key('new-event-button'),
                onPressed: open,
                icon: const Icon(Icons.event_available_outlined, size: 18),
                label: const Text('New event'),
              ),
            ),
    );
  }

  /// Below this width the new event button is an icon, so that the row of the
  /// days never overflows next to the span menu.
  static const double _labelledNavWidth = 760;

  /// Below this width the span menu shows an icon instead of its name.
  static const double _compactNavWidth = 440;

  static IconData _spanIcon(PlannerSpan span) => switch (span) {
        PlannerSpan.week => Icons.view_week_outlined,
        PlannerSpan.threeDays => Icons.view_column_outlined,
        PlannerSpan.day => Icons.view_day_outlined,
      };

  /// A button that names the span and opens the list of spans. When
  /// [compact], it shows the icon of the span instead of its name.
  Widget _spanMenu({required bool compact}) => PopupMenuButton<PlannerSpan>(
        key: const Key('planner-span-button'),
        tooltip: 'Choose how many days to show',
        initialValue: widget.span,
        onSelected: widget.onSpan,
        itemBuilder: (_) => [
          for (final s in PlannerSpan.values)
            PopupMenuItem(
              key: Key('planner-span-${s.name}'),
              value: s,
              child: Row(children: [
                Icon(_spanIcon(s), size: 20),
                const SizedBox(width: Space.sm),
                Text(s.label),
              ]),
            ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: Space.sm, vertical: Space.xs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (compact)
                Icon(_spanIcon(widget.span),
                    semanticLabel: widget.span.label, size: 20)
              else
                Text(widget.span.label,
                    style: Theme.of(context).textTheme.labelLarge),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
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
              Expanded(child: _DayHeader(day: d, today: _sameDay(d, _now))),
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
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant))),
              ),
              for (final d in days)
                Expanded(
                    child: _allDayCell(
                        d, _itemsOnDay(all, d, allDay: true), pending)),
            ],
          ),
        ),
        const SizedBox(height: Space.xs),
        const Divider(height: 1),
        Expanded(
          child: KeyedSubtree(
            key: _gridKey,
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
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant)),
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
                      scroll: _scroll,
                      onDragNearEdge: _autoScroll,
                    )),
                ],
              ),
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
      builder: (context, candidates, _) {
        final colors = context.tefteri;
        final hover = candidates.isNotEmpty;
        final dragging = ref.watch(dragActiveProvider);
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          // A right click on the empty all-day row offers an all-day event or
          // a task for this day.
          onSecondaryTapUp: (d) =>
              showSlotMenu(context, d.globalPosition, start: day, allDay: true),
          child: NoBrowserMenu(
            child: Container(
              constraints: const BoxConstraints(minHeight: 28),
              margin: const EdgeInsets.all(1),
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: hover
                    ? colors.taskContainer
                    : dragging
                        ? _veilColor(context)
                        : null,
                border: Border.all(
                    color: hover ? colors.task : Theme.of(context).dividerColor,
                    width: hover ? 2 : 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (hover)
                    Text('All day',
                        key: const Key('drop-preview-allday'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(color: colors.task)),
                  for (final i in items)
                    _AllDayChip(item: i, pending: pending == i.id),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The event that a drag carries when the user can move it: a timed event of a
/// calendar that is not read-only. Null for anything else.
CalendarItem? _movableEvent(Object data) =>
    data is CalendarItem && data.movable ? data : null;

/// What the calendar takes in a drop on a day: a task, or a movable event.
bool _dropAccepted(Object data) =>
    _taskIdOf(data) != null || _movableEvent(data) != null;

/// Task id carried by a dragged task row or task block; null for others.
String? _taskIdOf(Object data) {
  if (data is PlanTask) return data.id;
  if (data is CalendarItem && data.isTask) return data.id;
  return null;
}

/// The grey wash over the calendar during a drag. It fades the blocks and
/// tints the empty hours, so the whole calendar reads as "not the target".
Color _veilColor(BuildContext context) => Color.alphaBlend(
      Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.14),
      context.tefteri.paper.withValues(alpha: 0.5),
    );

/// Title of a dragged task row or task block; null for others.
String? _titleOf(Object data) {
  if (data is PlanTask) return data.title;
  if (data is CalendarItem && (data.isTask || data.movable)) return data.title;
  return null;
}

/// The preview of a drop of [data] on [day] at [minutes]; null for things that
/// the calendar does not take.
DropPreview? _previewOf(Object data, DateTime day, int minutes) {
  final title = _titleOf(data);
  if (title == null) return null;
  final event = _movableEvent(data);
  if (event == null) {
    return DropPreview(day: day, title: title, startMinutes: minutes);
  }
  final length = (event.end ?? event.start!.add(const Duration(hours: 1)))
      .difference(event.start!)
      .inMinutes;
  return DropPreview(
    day: day,
    title: title,
    startMinutes: minutes,
    durationMinutes: length < 15 ? 15 : length,
    event: true,
    color: event.color,
  );
}

Color _blockColor(BuildContext context, CalendarItem i) {
  // An event has the color that the user chose for its calendar, and a task
  // the color of its project. Without one, the colors of the app.
  final chosen = parseCalendarColor(i.color);
  if (chosen != null && !(i.isTask && i.isDone)) {
    return calendarTint(context, chosen);
  }
  return i.isTask
      ? context.tefteri.taskContainer
      : context.tefteri.eventContainer;
}

/// The strong color on the left edge of a block: the color that the user chose
/// for the calendar of an event or the project of a task. Without one, tasks
/// are terracotta and events ink blue. Finished tasks are sage.
Color _accentColor(BuildContext context, CalendarItem i) {
  final c = context.tefteri;
  if (!i.isTask) return parseCalendarColor(i.color) ?? c.event;
  if (i.isDone) return c.done;
  return parseCalendarColor(i.color) ?? c.task;
}

/// The fill of a block of an event that several calendars hold: the tint of
/// each calendar in turn, in diagonal bands with sharp edges, so that the
/// block reads as belonging to all of them. Null for other items.
Gradient? _sharedFill(BuildContext context, CalendarItem i) {
  if (!i.isShared) return null;
  final tints = [
    for (final hex in i.calendarColors)
      calendarTint(context, parseCalendarColor(hex) ?? context.tefteri.event),
  ];
  final colors = <Color>[];
  final stops = <double>[];
  for (var n = 0; n < tints.length; n++) {
    colors.addAll([tints[n], tints[n]]);
    stops.addAll([n / tints.length, (n + 1) / tints.length]);
  }
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: colors,
    stops: stops,
  );
}

/// The strong bar on the left edge of a block, with [key]. An event that
/// several calendars hold has one segment in the color of each calendar.
Widget _accentBar(BuildContext context, CalendarItem item, Key key) {
  if (!item.isShared) {
    return Container(key: key, width: 3, color: _accentColor(context, item));
  }
  return SizedBox(
    key: key,
    width: 3,
    child: Column(
      children: [
        for (final hex in item.calendarColors)
          Expanded(
            child: ColoredBox(
                color: parseCalendarColor(hex) ?? context.tefteri.event),
          ),
      ],
    ),
  );
}

/// A small mark on a block of an event that several calendars hold.
class _SharedMark extends StatelessWidget {
  const _SharedMark({required this.item});

  final CalendarItem item;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 2),
        child: Icon(Icons.layers_outlined,
            key: Key('shared-${item.id}'),
            size: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
}

/// A small label with a solid background and square corners that names the
/// project of a task, so that it can be read without opening the task.
class _ProjectTag extends StatelessWidget {
  const _ProjectTag(
      {required this.name,
      required this.maxWidth,
      this.work = false,
      super.key});

  final String name;

  /// The project is work: a small briefcase goes before the name.
  final bool work;

  /// The widest the tag may be; a longer name is cut with dots.
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: work ? 'Project: $name (work)' : 'Project: $name',
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth < 24 ? 24 : maxWidth),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          // Square corners and a solid fill: dark ink on light paper, and
          // the reverse in the dark theme.
          color: scheme.onSurfaceVariant,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (work) ...[
                Icon(Icons.work_outline, size: 10, color: scheme.surface),
                const SizedBox(width: 2),
              ],
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        height: 1.2,
                        color: scheme.surface,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AllDayChip extends StatelessWidget {
  const _AllDayChip({required this.item, required this.pending});

  final CalendarItem item;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme.labelSmall;
    final chip = _OpenDetails(
        item: item,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Corner.sm),
          child: Container(
            key: Key('allday-${item.type}-${item.id}'),
            margin: const EdgeInsets.symmetric(vertical: 1),
            constraints: const BoxConstraints(minHeight: 22),
            padding:
                const EdgeInsets.only(left: 7, right: 3, top: 3, bottom: 3),
            decoration: BoxDecoration(
              color: _blockColor(context, item),
              // An event of several calendars has the tint of each of them.
              gradient: _sharedFill(context, item),
              // The accent bar on the left edge.
              border: Border(
                  left:
                      BorderSide(color: _accentColor(context, item), width: 3)),
            ),
            child: _chipBody(text),
          ),
        ));
    if (!item.isTask) return chip;
    return PlannerDraggable<CalendarItem>(
        data: item, label: item.title, dimmed: pending, child: chip);
  }

  Widget _chipBody(TextStyle? text) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Expanded(
              child: Text(item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text?.copyWith(
                      decoration:
                          item.isDone ? TextDecoration.lineThrough : null)),
            ),
            if (item.isShared) _SharedMark(item: item),
          ]),
          if (item.project != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              // Flexible: the tag takes its own width, up to the chip.
              child: Row(children: [
                Flexible(
                  child: _ProjectTag(
                      key: Key('project-tag-${item.id}'),
                      name: item.project!,
                      work: item.work,
                      maxWidth: double.infinity),
                ),
              ]),
            ),
        ],
      );
}

class _DayColumn extends ConsumerStatefulWidget {
  const _DayColumn({
    required this.day,
    required this.items,
    required this.pending,
    required this.now,
    required this.scroll,
    required this.onDragNearEdge,
  });

  final DateTime day;
  final List<CalendarItem> items;
  final String? pending;

  /// The current time when [day] is today; null on other days.
  final DateTime? now;

  /// The scroll controller of the grid. The preview follows its scrolling.
  final ScrollController scroll;

  /// Told where the pointer is (global) while a task is dragged over the
  /// column, so that the grid can scroll near its edges.
  final void Function(Offset pointer) onDragNearEdge;

  @override
  ConsumerState<_DayColumn> createState() => _DayColumnState();
}

class _DayColumnState extends ConsumerState<_DayColumn> {
  /// Stays the same across rebuilds, so that the drop preview can animate.
  final _boxKey = GlobalKey();

  /// The global pointer position while a task is held over this column.
  Offset? _pointer;

  @override
  void initState() {
    super.initState();
    widget.scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.scroll.removeListener(_onScroll);
    super.dispose();
  }

  /// The grid moved under a pointer that did not: the slot under it changed,
  /// and a drop now would use the new one, so the preview must too.
  void _onScroll() {
    if (_pointer == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pointer = _pointer;
      final current = ref.read(dropPreviewProvider);
      if (!mounted ||
          pointer == null ||
          current == null ||
          current.day != day) {
        return;
      }
      final next = current.at(_minutesAt(pointer));
      if (next != current) ref.read(dropPreviewProvider.notifier).state = next;
    });
  }

  DateTime get day => widget.day;
  List<CalendarItem> get items => widget.items;
  String? get pending => widget.pending;
  DateTime? get now => widget.now;

  /// Where a drop at the global point [pointer] would put the block.
  int _minutesAt(Offset pointer) {
    final box = _boxKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return 0;
    return snapMinutes(offsetToMinutes(box.globalToLocal(pointer).dy));
  }

  void _clearPreview() {
    final now = ref.read(dropPreviewProvider);
    if (now != null && now.day == day) {
      ref.read(dropPreviewProvider.notifier).state = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final boxKey = _boxKey;
    final dragging = ref.watch(dragActiveProvider);
    final preview = ref.watch(dropPreviewProvider);
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
      onWillAcceptWithDetails: (d) => _dropAccepted(d.data),
      onMove: (d) {
        _pointer = d.offset;
        final next = _previewOf(d.data, day, _minutesAt(d.offset));
        if (next == null) return;
        if (ref.read(dropPreviewProvider) != next) {
          ref.read(dropPreviewProvider.notifier).state = next;
        }
        widget.onDragNearEdge(d.offset);
      },
      onLeave: (_) {
        _pointer = null;
        _clearPreview();
      },
      onAcceptWithDetails: (d) {
        final id = _taskIdOf(d.data);
        final event = _movableEvent(d.data);
        final box = boxKey.currentContext?.findRenderObject() as RenderBox?;
        _pointer = null;
        ref.read(dropPreviewProvider.notifier).state = null;
        if ((id == null && event == null) || box == null) return;
        final start = slotStart(day, box.globalToLocal(d.offset).dy);
        final actions = ref.read(plannerActionsProvider);
        if (event != null) {
          // An event that did not move needs no save.
          if (event.start!.toLocal() != start) actions.moveEntry(event, start);
        } else {
          actions.scheduleAt(id!, start);
        }
      },
      builder: (context, candidates, _) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        // A right click on an empty slot offers a new event or a new task. A
        // block takes its own right click (see _OpenDetails), so this is only
        // reached by a click on an empty slot.
        onSecondaryTapUp: (d) {
          final box = boxKey.currentContext?.findRenderObject() as RenderBox?;
          if (box == null) return;
          final start = slotStart(day, box.globalToLocal(d.globalPosition).dy);
          showSlotMenu(context, d.globalPosition, start: start);
        },
        child: NoBrowserMenu(
          child: Container(
            key: boxKey,
            height: hourHeight * 24,
            decoration: BoxDecoration(
              color: candidates.isNotEmpty
                  ? Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withValues(alpha: 0.5)
                  : now != null
                      ? context.tefteri.today
                      : day.weekday >= DateTime.saturday
                          ? context.tefteri.weekend
                          : null,
              border: Border(
                  left: BorderSide(color: Theme.of(context).dividerColor)),
            ),
            child: LayoutBuilder(
              builder: (context, c) => Stack(
                key: Key('day-column-${dateKey(day)}'),
                clipBehavior: Clip.hardEdge,
                children: [
                  for (var h = 0; h < 24; h++) ...[
                    if (h > 0)
                      Positioned(
                        top: h * hourHeight,
                        left: 0,
                        right: 0,
                        child: Divider(height: 1, color: context.tefteri.rule),
                      ),
                    // a fainter line at the half hour
                    Positioned(
                      top: h * hourHeight + hourHeight / 2,
                      left: 0,
                      right: 0,
                      child: Divider(
                          height: 1,
                          color: context.tefteri.rule.withValues(alpha: 0.4)),
                    ),
                  ],
                  for (var n = 0; n < items.length; n++)
                    _block(context, items[n], spans[n], layout[n], c.maxWidth),
                  if (now != null) _nowLine(context, now!),
                  // While a task is dragged, everything fades back, and only the
                  // slot under the pointer shows where the task would land.
                  _scrim(context, dragging),
                  if (dragging && preview != null && preview.day == day)
                    _previewBlock(context, preview),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A veil over the column that fades in during a drag. It takes no pointer
  /// events, so the drop still reaches the column.
  Widget _scrim(BuildContext context, bool dragging) => Positioned.fill(
        child: IgnorePointer(
          child: AnimatedOpacity(
            key: Key('drag-scrim-${dateKey(day)}'),
            opacity: dragging ? 1 : 0,
            duration: Motion.of(context, Motion.quick),
            child: ColoredBox(color: _veilColor(context)),
          ),
        ),
      );

  /// The one-hour block where the dragged task would land, with its times.
  Widget _previewBlock(BuildContext context, DropPreview p) {
    final colors = context.tefteri;
    final text = Theme.of(context).textTheme;
    final start = p.startMinutes ?? 0;
    final end = start + p.durationMinutes;
    final chosen = parseCalendarColor(p.color);
    final fill = p.event
        ? (chosen == null
            ? colors.eventContainer
            : calendarTint(context, chosen))
        : colors.taskContainer;
    final edge = p.event ? (chosen ?? colors.event) : colors.task;
    final height =
        minutesToOffset((end > minutesPerDay ? minutesPerDay : end) - start);
    String hm(int m) =>
        '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
    return AnimatedPositioned(
      key: const Key('drop-preview'),
      duration: Motion.of(context, Motion.quick),
      curve: Motion.enter,
      top: minutesToOffset(start),
      left: 1,
      right: 1,
      height: height,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(Corner.sm),
            border: Border.all(color: edge, width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Scales down in a narrow column, so that the end time shows too.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                    '${hm(start)} - ${hm(end > minutesPerDay ? minutesPerDay : end)}',
                    key: const Key('drop-preview-time'),
                    maxLines: 1,
                    style: text.labelMedium?.copyWith(color: edge)),
              ),
              if (height >= 36)
                Text(p.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelSmall),
            ],
          ),
        ),
      ),
    );
  }

  /// The red dot and line at the current time, as in Google Calendar. It does
  /// not take pointer events, so a drop still reaches the column.
  Widget _nowLine(BuildContext context, DateTime now) {
    const dot = 10.0;
    final color = context.tefteri.now;
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
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            Expanded(
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
    final project = i.project;
    // A short block has room for one line: the tag sits after the title. A
    // taller block gives the tag its own line under the title.
    final inlineTag = project != null && height < 40;
    final tagLine = project != null && !inlineTag;
    final showTime = height >= (project != null ? 50 : 40);
    final body = _OpenDetails(
        item: i,
        child: Container(
          key: Key('block-${i.type}-${i.id}'),
          margin: const EdgeInsets.all(1),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: _blockColor(context, i),
            // An event of several calendars has the tint of each of them.
            gradient: _sharedFill(context, i),
            borderRadius: BorderRadius.circular(Corner.sm),
          ),
          // A strong edge on the left and a tint: terracotta for tasks, ink
          // blue for events, sage once a task is done.
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _accentBar(context, i, Key('block-accent-${i.type}-${i.id}')),
              Expanded(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(i.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                        decoration: i.isDone
                                            ? TextDecoration.lineThrough
                                            : null)),
                          ),
                          if (inlineTag) ...[
                            const SizedBox(width: 3),
                            _ProjectTag(
                                key: Key('project-tag-${i.id}'),
                                name: project,
                                work: i.work,
                                maxWidth: colWidth * 0.45),
                          ],
                          if (i.isShared) _SharedMark(item: i),
                          if (i.clippedStart)
                            Tooltip(
                              message: 'Continues from previous day',
                              child: Icon(Icons.subdirectory_arrow_right,
                                  key: Key('clipped-${i.id}'), size: 12),
                            ),
                        ],
                      ),
                      if (tagLine)
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: _ProjectTag(
                              key: Key('project-tag-${i.id}'),
                              name: project,
                              work: i.work,
                              maxWidth: colWidth - 14),
                        ),
                      if (showTime)
                        Text(time,
                            maxLines: 1,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ));
    return Positioned(
      top: minutesToOffset(span.$1),
      left: colWidth * place.column,
      width: colWidth,
      height: height,
      child: i.isTask || i.movable
          ? PlannerDraggable<CalendarItem>(
              data: i,
              label: i.title,
              dimmed: isPending,
              feedbackColor: i.isTask ? null : _blockColor(context, i),
              child: body)
          : body,
    );
  }
}

/// Weekday and date of one column. Today's date sits in a filled circle.
class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.today});

  final DateTime day;
  final bool today;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_weekdays[day.weekday - 1],
                style: text.labelSmall?.copyWith(
                    color: today ? scheme.primary : scheme.onSurfaceVariant)),
            const SizedBox(width: 4),
            Container(
              constraints: const BoxConstraints(minWidth: 24),
              height: 24,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: today
                  ? BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(Corner.pill))
                  : null,
              child: Text('${day.day}',
                  style: text.titleSmall?.copyWith(
                      color: today ? scheme.onPrimary : scheme.onSurface)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the details pop-up of [item] when the user taps [child]: the task for
/// a task block, the event for an event. A mouse resting on [child] shows the
/// details in a tooltip.
///
/// Ctrl and a click on a task block mark the task as done, and open nothing. A
/// task that is done stays as it is (no second click reopens it by mistake),
/// and events have nothing to complete.
class _OpenDetails extends ConsumerWidget {
  const _OpenDetails({required this.item, required this.child});

  final CalendarItem item;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ControlKey.watch();
    // Resting the mouse on a block shows its whole title and details. Touch
    // has no hover, and a long press there drags, so it shows nothing.
    return Tooltip(
      key: Key('item-tooltip-${item.type}-${item.id}'),
      message: itemTooltip(item),
      triggerMode: TooltipTriggerMode.manual,
      waitDuration: const Duration(milliseconds: 400),
      child: _gesture(context, ref),
    );
  }

  Widget _gesture(BuildContext context, WidgetRef ref) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        // A right click on a block does nothing. This also keeps it from
        // reaching the day column, which offers a new event on an empty slot.
        onSecondaryTap: () {},
        onTap: () {
          if (item.isTask && ControlKey.heldRecently) {
            if (!item.isDone) {
              ref.read(plannerActionsProvider).complete(item.id);
            }
            return;
          }
          item.isTask
              ? showTaskDetails(context, taskId: item.id, title: item.title)
              : showEventDetails(context, item);
        },
        child: child,
      );
}
