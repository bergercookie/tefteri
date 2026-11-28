/// The default planning screen: tasks on the left, the calendar on the right.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_error.dart';
import '../../core/pane_widths.dart';
import '../../core/planning_api.dart';
import '../../core/planning_models.dart';
import '../../core/shell.dart';
import '../settings/sync_controller.dart';
import '../add/add_menu.dart';
import '../daily/daily_note_button.dart';
import 'calendar_pane.dart';
import 'details_dialogs.dart';
import 'planner_providers.dart';
import 'planner_span.dart';
import 'planner_visibility.dart';
import 'planner_views_dialog.dart';
import 'new_task_dialog.dart';
import 'schedule_dialog.dart';
import 'task_pane.dart';

/// The calendar keeps at least this much width when the task list grows.
const double calendarMinWidth = 460;

/// Below this width two columns do not fit and the screen uses two tabs.
const double twoColumnMinWidth = 840;

/// Shows the task column and the calendar side by side. Drag a task onto a
/// time slot to plan it; the due date in the task app is set for you.
class PlannerScreen extends ConsumerStatefulWidget {
  /// Creates the screen; the calendar shows the days that hold
  /// [initialDate] (default today): its week, or the day and the days after
  /// it, as the user chose.
  const PlannerScreen(
      {this.initialDate,
      this.openTaskId,
      this.openEventId,
      this.openAdd,
      this.clock = DateTime.now,
      super.key});

  /// A day to show first.
  final DateTime? initialDate;

  /// A task whose details open at once (the user tapped its notification).
  final String? openTaskId;

  /// An event whose details open at once (the user tapped its notification).
  final String? openEventId;

  /// What to add at once (the user tapped the plus of the widget): `menu` opens the Add menu, and
  /// `note`, `task` or `event` open that form.
  final String? openAdd;

  /// Gives the current time (the red line on the calendar). Tests replace it.
  final DateTime Function() clock;

  @override
  ConsumerState<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends ConsumerState<PlannerScreen> {
  /// The day the user looks at. The calendar starts on it, or on the Monday
  /// before it in the week view.
  late DateTime _anchor;
  int _tab = 0;

  /// The width that the calendar has now; it decides the span while the user
  /// has not chosen one.
  double _calendarWidth = twoColumnMinWidth;

  late final StateController<PlannerUndo?> _undoState;

  @override
  void dispose() {
    // Leaving the planner: an old move can no longer be undone from here.
    Future.microtask(() {
      try {
        _undoState.state = null;
      } on Object {
        // The app is closing.
      }
    });
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _undoState = ref.read(plannerUndoProvider.notifier);
    _anchor = _dayOf(widget.initialDate ?? widget.clock());
    WidgetsBinding.instance.addPostFrameCallback((_) => _openLinked());
  }

  @override
  void didUpdateWidget(PlannerScreen old) {
    super.didUpdateWidget(old);
    // A notification tapped while the planner is open gives the same screen new values.
    if (widget.openTaskId != old.openTaskId ||
        widget.openEventId != old.openEventId ||
        widget.openAdd != old.openAdd) {
      if (widget.initialDate != null) {
        _anchor = _dayOf(widget.initialDate!);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _openLinked());
    }
  }

  /// Takes the task, event and add parts out of the address once they are used. The same link
  /// then works again: a second tap of the same row of the widget is a change of the address.
  void _forgetLink() {
    final router = GoRouter.maybeOf(context);
    if (router == null) return;
    final day = dateKey(_anchor);
    router.go('/?date=$day');
  }

  /// Opens the pop-up of the task or the event that the link names.
  Future<void> _openLinked() async {
    if (!mounted) return;
    final taskId = widget.openTaskId;
    final eventId = widget.openEventId;
    final add = widget.openAdd;
    final linked = (taskId?.isNotEmpty ?? false) ||
        (eventId?.isNotEmpty ?? false) ||
        (add?.isNotEmpty ?? false);
    if (linked) _forgetLink();
    if (add != null && add.isNotEmpty) {
      switch (add) {
        case 'note':
          await showDailyNoteSheet(context);
        case 'task':
          await showNewTaskDialog(context);
        case 'event':
          await startNewEvent(context);
        default:
          await showAddMenu(context);
      }
    } else if (taskId != null && taskId.isNotEmpty) {
      await showTaskDetails(context, taskId: taskId);
    } else if (eventId != null && eventId.isNotEmpty) {
      final day = _dayOf(widget.initialDate ?? widget.clock());
      try {
        final items = await ref
            .read(planningApiProvider)
            .calendar(day, DateTime(day.year, day.month, day.day + 1));
        final event = items.where((i) => !i.isTask && i.id == eventId);
        if (!mounted || event.isEmpty) return;
        await showEventDetails(context, event.first);
      } on DioException catch (e) {
        ref.read(plannerErrorProvider.notifier).state = apiErrorMessage(e);
      }
    }
  }

  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  PlannerSpan get _span =>
      ref.read(plannerSpanProvider) ?? spanForWidth(_calendarWidth);

  DateTime get _start => _span.startFor(_anchor);

  /// Moves by [steps] spans: a week, three days or one day.
  void _shift(int steps) => setState(() => _anchor =
      DateTime(_anchor.year, _anchor.month, _anchor.day + steps * _span.days));

  /// Shows [chosen], or the span that fits the width when it is null. When today is on the screen, the new view holds it too;
  /// otherwise it starts where the old one starts.
  void _setSpan(PlannerSpan? chosen) {
    final today = _dayOf(widget.clock());
    final start = _start;
    final end = DateTime(start.year, start.month, start.day + _span.days);
    setState(() => _anchor =
        !today.isBefore(start) && today.isBefore(end) ? today : start);
    ref.read(plannerSpanProvider.notifier).set(chosen);
  }

  void _undo() => ref.read(plannerActionsProvider).undo();

  @override
  Widget build(BuildContext context) {
    ref.listen<SyncState>(syncControllerProvider, (prev, next) {
      if (prev != null && prev.busy && !next.busy) {
        ref.read(plannerActionsProvider).refresh();
      }
    });
    // After an event was moved or resized: a message with Undo, for a few seconds.
    ref.listen<PlannerUndo?>(plannerUndoProvider, (prev, next) {
      final messenger = ScaffoldMessenger.of(context);
      if (next == null) {
        messenger.hideCurrentSnackBar();
        return;
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          key: const Key('undo-snackbar'),
          content: Text(next.message),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => ref.read(plannerActionsProvider).undo(),
          ),
        ));
    });
    final error = ref.watch(plannerErrorProvider);
    final visibility = ref.watch(plannerVisibilityProvider);
    ref.watch(plannerSpanProvider); // the calendar follows the span
    return AppShell(
      title: 'Planner',
      fullBleed: true,
      actions: IconButton(
        key: const Key('planner-views-button'),
        tooltip: 'Choose what the planner shows',
        icon: Icon(visibility.showTasks &&
                visibility.showCalendar &&
                !visibility.hasHiddenSources
            ? Icons.visibility_outlined
            : Icons.visibility_off_outlined),
        onPressed: () => showPlannerViewsDialog(context),
      ),
      // Left and right arrow move by one week, three days or one day. A text
      // field handles the arrows itself first (to move the cursor), so typing
      // is not affected.
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _shift(-1),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () => _shift(1),
          // Ctrl+Z (Cmd+Z on a Mac) takes back the last move of an event. A text field handles
          // the key itself first, to undo its own typing.
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
          const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): _undo,
        },
        child: Focus(
          autofocus: true,
          child: Column(
            children: [
              if (error != null)
                ErrorBanner(
                  message: error,
                  onDismiss: () =>
                      ref.read(plannerErrorProvider.notifier).state = null,
                ),
              Expanded(
                child: LayoutBuilder(builder: (context, c) {
                  final wide = c.maxWidth >= twoColumnMinWidth;
                  _calendarWidth =
                      wide ? _wideCalendarWidth(c.maxWidth) : c.maxWidth;
                  return wide ? _wide(c.maxWidth) : _narrow();
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  CalendarPane _calendar() => CalendarPane(
        start: _start,
        span: _span,
        onShift: _shift,
        onSpan: _setSpan,
        automatic: ref.read(plannerSpanProvider) == null,
        clock: widget.clock,
        onToday: () => setState(() => _anchor = _dayOf(widget.clock())),
      );

  /// The width of the calendar next to the task list.
  double _wideCalendarWidth(double available) {
    final visibility = ref.read(plannerVisibilityProvider);
    if (!visibility.showCalendar) return available;
    if (!visibility.showTasks) return available;
    final notifier = ref.read(taskPaneWidthProvider.notifier);
    final most = (available - calendarMinWidth - resizeHandleWidth)
        .clamp(notifier.min, notifier.max)
        .toDouble();
    final width = ref.read(taskPaneWidthProvider).clamp(notifier.min, most);
    return available - width - resizeHandleWidth;
  }

  Widget _wide(double available) {
    final visibility = ref.watch(plannerVisibilityProvider);
    if (!visibility.showCalendar) {
      return TaskPane(onScheduleTask: _chooseTime);
    }
    if (!visibility.showTasks) return _calendar();
    final notifier = ref.read(taskPaneWidthProvider.notifier);
    // The task list is as wide as the user dragged it, and leaves the
    // calendar its minimum.
    final most = (available - calendarMinWidth - resizeHandleWidth)
        .clamp(notifier.min, notifier.max)
        .toDouble();
    final width = ref.watch(taskPaneWidthProvider).clamp(notifier.min, most);
    return Row(
      children: [
        SizedBox(width: width, child: const TaskPane()),
        ResizeHandle(
          key: const Key('task-pane-resize'),
          label: 'Resize the task list',
          onDrag: (dx) => notifier.by(dx, cap: most),
          onEnd: notifier.save,
          onReset: notifier.reset,
        ),
        Expanded(child: _calendar()),
      ],
    );
  }

  /// Two tabs that stay alive, so the filter, the search text and the days
  /// survive a switch. Tasks are scheduled with a dialog instead of a drag.
  /// When the user hides one pane, the other fills the screen.
  Widget _narrow() {
    final visibility = ref.watch(plannerVisibilityProvider);
    if (!visibility.showCalendar) {
      return TaskPane(onScheduleTask: _chooseTime);
    }
    if (!visibility.showTasks) return _calendar();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: SegmentedButton<int>(
            key: const Key('planner-tabs'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                  value: 0,
                  label: Text('Tasks', key: Key('tab-tasks')),
                  icon: Icon(Icons.checklist)),
              ButtonSegment(
                  value: 1,
                  label: Text('Calendar', key: Key('tab-calendar')),
                  icon: Icon(Icons.calendar_month)),
            ],
            selected: {_tab},
            onSelectionChanged: (s) => setState(() => _tab = s.first),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _tab,
            children: [
              TaskPane(onScheduleTask: _chooseTime),
              _calendar(),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _chooseTime(PlanTask task) async {
    final start = _start;
    final days = [
      for (var i = 0; i < 14; i++)
        DateTime(start.year, start.month, start.day + i),
    ];
    final now = widget.clock();
    final today = DateTime(now.year, now.month, now.day);
    final base = task.dueAt != null && task.scheduledStart != null
        ? task.scheduledStart!.toLocal()
        : (days.contains(today) ? today : days.first);
    final initial = task.scheduledStart != null
        ? base
        : DateTime(base.year, base.month, base.day, defaultScheduleHour);
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (_) => ScheduleDialog(days: days, initial: initial),
    );
    if (picked != null) {
      await ref.read(plannerActionsProvider).scheduleAt(task.id, picked);
    }
  }
}
