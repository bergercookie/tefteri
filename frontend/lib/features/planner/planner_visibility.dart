/// What the planner shows: its two panes, and the task and calendar sources.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The parts of the planner that the user switched off.
///
/// Hiding a source changes only the view. The data keeps syncing, so the user
/// can show it again at once. The choice is kept on this device.
@immutable
class PlannerVisibility {
  /// Creates a visibility state with everything on.
  const PlannerVisibility({
    this.showTasks = true,
    this.showCalendar = true,
    this.hiddenTaskConnectionIds = const {},
    this.hiddenCalendarIds = const {},
  });

  /// True when the task pane is shown.
  final bool showTasks;

  /// True when the calendar pane is shown.
  final bool showCalendar;

  /// Task connections whose tasks are hidden in the planner.
  final Set<String> hiddenTaskConnectionIds;

  /// Calendars whose events are hidden in the planner.
  final Set<String> hiddenCalendarIds;

  /// True when tasks from [connectionId] are shown.
  bool showsTaskConnection(String? connectionId) =>
      connectionId == null || !hiddenTaskConnectionIds.contains(connectionId);

  /// True when events of calendar [containerId] are shown.
  bool showsCalendar(String? containerId) =>
      containerId == null || !hiddenCalendarIds.contains(containerId);

  /// True when at least one source is hidden.
  bool get hasHiddenSources =>
      hiddenTaskConnectionIds.isNotEmpty || hiddenCalendarIds.isNotEmpty;

  /// Returns a copy with changed fields.
  PlannerVisibility copyWith({
    bool? showTasks,
    bool? showCalendar,
    Set<String>? hiddenTaskConnectionIds,
    Set<String>? hiddenCalendarIds,
  }) =>
      PlannerVisibility(
        showTasks: showTasks ?? this.showTasks,
        showCalendar: showCalendar ?? this.showCalendar,
        hiddenTaskConnectionIds:
            hiddenTaskConnectionIds ?? this.hiddenTaskConnectionIds,
        hiddenCalendarIds: hiddenCalendarIds ?? this.hiddenCalendarIds,
      );
}

/// Keeps [PlannerVisibility] and stores it on this device.
class PlannerVisibilityController extends StateNotifier<PlannerVisibility> {
  /// Creates the controller and loads the saved choice.
  PlannerVisibilityController() : super(const PlannerVisibility()) {
    _load();
  }

  static const _showTasksKey = 'planner_show_tasks';
  static const _showCalendarKey = 'planner_show_calendar';
  static const _hiddenTaskConnectionsKey = 'planner_hidden_task_connections';
  static const _hiddenCalendarsKey = 'planner_hidden_calendars';

  bool _userChanged = false;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted || _userChanged) return;
      final showTasks = prefs.getBool(_showTasksKey) ?? true;
      final showCalendar = prefs.getBool(_showCalendarKey) ?? true;
      state = PlannerVisibility(
        // A stored state with both panes off would leave an empty screen.
        showTasks: showTasks || !showCalendar,
        showCalendar: showCalendar,
        hiddenTaskConnectionIds:
            (prefs.getStringList(_hiddenTaskConnectionsKey) ?? const [])
                .toSet(),
        hiddenCalendarIds:
            (prefs.getStringList(_hiddenCalendarsKey) ?? const []).toSet(),
      );
    } on Object {
      // The choice is only a convenience: keep everything on.
    }
  }

  /// Shows or hides the task pane. The calendar stays visible when it is the
  /// only pane left.
  void setShowTasks(bool value) {
    if (!value && !state.showCalendar) return;
    _apply(state.copyWith(showTasks: value));
  }

  /// Shows or hides the calendar pane. The tasks stay visible when they are
  /// the only pane left.
  void setShowCalendar(bool value) {
    if (!value && !state.showTasks) return;
    _apply(state.copyWith(showCalendar: value));
  }

  /// Shows or hides the tasks of [connectionId].
  void setTaskConnectionVisible(String connectionId, bool visible) {
    final hidden = {...state.hiddenTaskConnectionIds};
    if (visible) {
      hidden.remove(connectionId);
    } else {
      hidden.add(connectionId);
    }
    _apply(state.copyWith(hiddenTaskConnectionIds: hidden));
  }

  /// Shows or hides the events of calendar [containerId].
  void setCalendarVisible(String containerId, bool visible) {
    final hidden = {...state.hiddenCalendarIds};
    if (visible) {
      hidden.remove(containerId);
    } else {
      hidden.add(containerId);
    }
    _apply(state.copyWith(hiddenCalendarIds: hidden));
  }

  /// Shows every task provider and calendar again.
  void showAllSources() {
    _apply(state.copyWith(
      hiddenTaskConnectionIds: const {},
      hiddenCalendarIds: const {},
    ));
  }

  void _apply(PlannerVisibility next) {
    _userChanged = true;
    state = next;
    _save();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_showTasksKey, state.showTasks);
      await prefs.setBool(_showCalendarKey, state.showCalendar);
      await prefs.setStringList(
          _hiddenTaskConnectionsKey, state.hiddenTaskConnectionIds.toList());
      await prefs.setStringList(
          _hiddenCalendarsKey, state.hiddenCalendarIds.toList());
    } on Object {
      // The choice is only a convenience: ignore a store that does not work.
    }
  }
}

/// The parts of the planner that the user chose to show.
final plannerVisibilityProvider =
    StateNotifierProvider<PlannerVisibilityController, PlannerVisibility>(
        (_) => PlannerVisibilityController());
