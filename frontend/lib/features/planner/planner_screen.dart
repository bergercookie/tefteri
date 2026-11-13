/// The default planning screen: tasks on the left, the calendar on the right.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/pane_widths.dart';
import '../../core/planning_models.dart';
import '../../core/shell.dart';
import '../settings/sync_controller.dart';
import 'calendar_pane.dart';
import 'planner_providers.dart';
import 'planner_visibility.dart';
import 'planner_views_dialog.dart';
import 'schedule_dialog.dart';
import 'task_pane.dart';

/// The calendar keeps at least this much width when the task list grows.
const double calendarMinWidth = 460;

/// Below this width two columns do not fit and the screen uses two tabs.
const double twoColumnMinWidth = 840;

/// Shows the task column and the calendar side by side. Drag a task onto a
/// time slot to plan it; the due date in the task app is set for you.
class PlannerScreen extends ConsumerStatefulWidget {
  /// Creates the screen; the calendar shows the week that holds
  /// [initialDate] (default today).
  const PlannerScreen({this.initialDate, this.clock = DateTime.now, super.key});

  /// A day in the week to show first.
  final DateTime? initialDate;

  /// Gives the current time (the red line on the calendar). Tests replace it.
  final DateTime Function() clock;

  @override
  ConsumerState<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends ConsumerState<PlannerScreen> {
  late DateTime _weekStart;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _weekStart = _mondayOf(widget.initialDate ?? widget.clock());
  }

  static DateTime _mondayOf(DateTime d) =>
      DateTime(d.year, d.month, d.day - (d.weekday - 1));

  void _shift(int weeks) => setState(() => _weekStart =
      DateTime(_weekStart.year, _weekStart.month, _weekStart.day + 7 * weeks));

  @override
  Widget build(BuildContext context) {
    ref.listen<SyncState>(syncControllerProvider, (prev, next) {
      if (prev != null && prev.busy && !next.busy) {
        ref.read(plannerActionsProvider).refresh();
      }
    });
    final error = ref.watch(plannerErrorProvider);
    final visibility = ref.watch(plannerVisibilityProvider);
    return AppShell(
      title: 'Planner',
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
      // Left and right arrow move by one week. A text field handles the
      // arrows itself first (to move the cursor), so typing is not affected.
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _shift(-1),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () => _shift(1),
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
                child: LayoutBuilder(
                  builder: (context, c) => c.maxWidth >= twoColumnMinWidth
                      ? _wide(c.maxWidth)
                      : _narrow(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  CalendarPane _calendar() => CalendarPane(
        weekStart: _weekStart,
        onShiftWeek: _shift,
        clock: widget.clock,
        onToday: () => setState(() => _weekStart = _mondayOf(widget.clock())),
      );

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

  /// Two tabs that stay alive, so the filter, the search text and the week
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
    final days = [
      for (var i = 0; i < 14; i++)
        DateTime(_weekStart.year, _weekStart.month, _weekStart.day + i),
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
