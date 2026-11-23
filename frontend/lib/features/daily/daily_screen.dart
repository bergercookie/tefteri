/// Daily view: entries, tasks and the daily note for one day.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/calendar_color.dart';
import '../../core/api_error.dart';
import '../../core/planning_api.dart';
import '../../core/planning_models.dart';
import '../../core/shell.dart';
import '../../theme/theme.dart';
import '../planner/details_dialogs.dart' show showTaskDetails;
import '../settings/connection_models.dart';
import '../settings/sync_controller.dart';
import 'daily_providers.dart';

/// Shows one day with quick add, complete, delete and note append.
///
/// The events that are over are faded. On today, the list starts at the first
/// event that has not ended, so the events that are over are scrolled out of
/// view.
class DailyScreen extends ConsumerStatefulWidget {
  /// Creates the screen; [initialDate] defaults to today.
  const DailyScreen({this.initialDate, super.key});

  /// Day to show first.
  final DateTime? initialDate;

  @override
  ConsumerState<DailyScreen> createState() => _DailyScreenState();
}

class _DailyScreenState extends ConsumerState<DailyScreen> {
  late DateTime _date;
  String? _error;
  String? _connectionId;
  final _titleCtl = TextEditingController();
  final _noteCtl = TextEditingController();
  final _scroll = ScrollController();

  /// The first event that has not ended; the list scrolls to it.
  final _anchorKey = GlobalKey();

  /// Every minute, so that an event fades when it ends.
  Timer? _tick;

  /// The day for which the list was scrolled already. It scrolls once for each
  /// time that the user comes to a day, not each time that the day reloads.
  String? _scrolledFor;

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate ?? _now;
    _syncTick();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _scroll.dispose();
    _titleCtl.dispose();
    _noteCtl.dispose();
    super.dispose();
  }

  DateTime get _now => ref.read(dailyClockProvider)();

  bool get _isToday => dateKey(_date) == dateKey(_now);

  /// Runs the minute timer only while today is shown.
  void _syncTick() {
    _tick?.cancel();
    _tick = _isToday
        ? Timer.periodic(const Duration(minutes: 1), (_) {
            if (mounted) setState(() {});
          })
        : null;
  }

  String get _key => dateKey(_date);

  /// Runs a write action. On failure the server message is shown and the
  /// change is dropped, never queued.
  Future<bool> _run(Future<void> Function() action) async {
    try {
      await action();
    } on DioException catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
      return false;
    }
    if (!mounted) return false;
    setState(() => _error = null);
    ref.invalidate(dayViewProvider(_key));
    return true;
  }

  List<Connection> get _taskConnections =>
      (ref.read(connectionsProvider).valueOrNull ?? const <Connection>[])
          .where((c) => c.kind == 'tasks')
          .toList();

  Future<void> _addTask() async {
    final title = _titleCtl.text.trim();
    if (title.isEmpty) return;
    final conns = _taskConnections;
    final id = conns.any((c) => c.id == _connectionId)
        ? _connectionId
        : conns.firstOrNull?.id;
    if (id == null) {
      setState(() =>
          _error = 'No task app is connected. Open Connections to add one.');
      return;
    }
    final ok = await _run(() => ref
        .read(planningApiProvider)
        .createTask(connectionId: id, title: title));
    if (ok) _titleCtl.clear();
  }

  Future<void> _appendNote() async {
    final text = _noteCtl.text.trim();
    if (text.isEmpty) return;
    final ok = await _run(
        () => ref.read(planningApiProvider).appendToDailyNote(_key, text));
    if (ok) _noteCtl.clear();
  }

  void _today() {
    setState(() {
      _date = _now;
      _error = null;
      _scrolledFor = null;
    });
    _syncTick();
  }

  void _shiftDay(int days) {
    setState(() {
      _date = DateTime(_date.year, _date.month, _date.day + days);
      _error = null;
      _scrolledFor = null;
    });
    _syncTick();
  }

  /// The event is over: it ended before [now], or it is an all-day event of a
  /// day that has passed.
  bool _isPast(PlanEntry e, DateTime now) {
    if (e.allDay) {
      final day = e.start?.toLocal();
      if (day == null) return false;
      return DateTime(day.year, day.month, day.day)
          .isBefore(DateTime(now.year, now.month, now.day));
    }
    final end = (e.end ?? e.start)?.toLocal();
    return end != null && !end.isAfter(now);
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(dayViewProvider(_key));
    return AppShell(
      title: 'Day $_key',
      body: Column(
        children: [
          if (_error != null)
            ErrorBanner(
                message: _error!,
                onDismiss: () => setState(() => _error = null)),
          _dayNav(),
          _quickAdd(),
          const Divider(height: 1),
          Expanded(
            child: view.when(
              loading: () => const Loading(),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(apiErrorMessage(e), key: const Key('load-error')),
                    TextButton(
                      key: const Key('reload-button'),
                      onPressed: () => ref.invalidate(dayViewProvider(_key)),
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
              data: _content,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dayNav() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          OutlinedButton(
            key: const Key('today-button'),
            onPressed: _today,
            child: const Text('Today'),
          ),
          const SizedBox(width: 8),
          IconButton(
            key: const Key('prev-day'),
            tooltip: 'Previous day',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _shiftDay(-1),
          ),
          Text(_key),
          IconButton(
            key: const Key('next-day'),
            tooltip: 'Next day',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _shiftDay(1),
          ),
        ],
      );

  Widget _quickAdd() {
    final conns =
        (ref.watch(connectionsProvider).valueOrNull ?? const <Connection>[])
            .where((c) => c.kind == 'tasks')
            .toList();
    final selected = conns.any((c) => c.id == _connectionId)
        ? _connectionId
        : conns.firstOrNull?.id;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('quick-add-field'),
              controller: _titleCtl,
              decoration: const InputDecoration(hintText: 'Add a task'),
              onSubmitted: (_) => _addTask(),
            ),
          ),
          if (conns.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: DropdownButton<String>(
                key: const Key('quick-add-connection'),
                value: selected,
                items: [
                  for (final c in conns)
                    DropdownMenuItem(value: c.id, child: Text(c.displayName)),
                ],
                onChanged: (v) => setState(() => _connectionId = v),
              ),
            ),
          IconButton(
            key: const Key('quick-add-button'),
            tooltip: 'Add task',
            icon: const Icon(Icons.add),
            onPressed: _addTask,
          ),
        ],
      ),
    );
  }

  Widget _content(DayView v) {
    final theme = Theme.of(context).textTheme;
    final now = _now;
    // On today, the list starts at the first event that is not over. When all
    // the events are over, it starts at the tasks. When no event is over yet,
    // it starts at the top, so that the heading Events shows.
    final anchorToday = _isToday && v.entries.isNotEmpty;
    final upcoming =
        anchorToday ? v.entries.indexWhere((e) => !_isPast(e, now)) : -1;
    final scrolls = anchorToday && upcoming != 0;
    if (scrolls && _scrolledFor != _key) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = _anchorKey.currentContext;
        if (!mounted || target == null || _scrolledFor == _key) return;
        _scrolledFor = _key;
        Scrollable.ensureVisible(target, alignment: 0, duration: Duration.zero);
      });
    }
    return LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
              key: const Key('day-list'),
              controller: _scroll,
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Events', style: theme.titleMedium),
                  if (v.entries.isEmpty) const Text('No events.'),
                  for (var i = 0; i < v.entries.length; i++)
                    i == upcoming
                        ? KeyedSubtree(
                            key: _anchorKey,
                            child: _entryTile(v.entries[i], now),
                          )
                        : _entryTile(v.entries[i], now),
                  const SizedBox(height: 16),
                  KeyedSubtree(
                    key: anchorToday && upcoming == -1 ? _anchorKey : null,
                    child: Text('Tasks', style: theme.titleMedium),
                  ),
                  if (v.tasks.isEmpty) const Text('No tasks.'),
                  for (final t in v.tasks) _taskTile(t),
                  const SizedBox(height: 16),
                  Text('Daily note', style: theme.titleMedium),
                  Text(
                    (v.note?.body.isNotEmpty ?? false)
                        ? v.note!.body
                        : 'No note yet.',
                    key: const Key('note-body'),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('note-field'),
                          controller: _noteCtl,
                          decoration: const InputDecoration(
                              hintText: 'Add to the note'),
                          onSubmitted: (_) => _appendNote(),
                        ),
                      ),
                      IconButton(
                        key: const Key('note-append-button'),
                        tooltip: 'Add to note',
                        icon: const Icon(Icons.send),
                        onPressed: _appendNote,
                      ),
                    ],
                  ),
                  // Room below, so that the next event can reach the top of the list
                  // also when little is below it.
                  if (scrolls) SizedBox(height: box.maxHeight * 0.8),
                ],
              ),
            ));
  }

  Widget _entryTile(PlanEntry e, DateTime now) {
    final colors = context.tefteri;
    final text = Theme.of(context).textTheme;
    final past = _isPast(e, now);
    final time = e.allDay || e.start == null
        ? 'All day'
        : '${hhmm(e.start!.toLocal())} - '
            '${e.end == null ? '' : hhmm(e.end!.toLocal())}';
    final place = (e.location?.isNotEmpty ?? false) ? ' - ${e.location}' : '';
    final tile = DecoratedBox(
      key: Key('entry-${e.id}'),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.rule)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The color of its calendar.
            Container(
              width: 4,
              margin: const EdgeInsets.symmetric(vertical: Space.sm),
              decoration: BoxDecoration(
                color: parseCalendarColor(e.color) ?? colors.task,
                borderRadius: BorderRadius.circular(Corner.sm),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: Space.md, vertical: Space.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w500)),
                    Text('$time$place${_syncNote(e.syncState)}',
                        style: text.bodySmall),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    // An event that is over is grayed out.
    return past
        ? Opacity(key: Key('entry-past-${e.id}'), opacity: 0.45, child: tile)
        : tile;
  }

  /// Marks the task done, or open again when it is done already.
  Future<void> _toggle(PlanTask t) => _run(() {
        final api = ref.read(planningApiProvider);
        return t.done ? api.reopenTask(t.id) : api.completeTask(t.id);
      });

  /// Opens the pop-up where the title, the due date and the rest can change,
  /// then loads the day again.
  Future<void> _edit(PlanTask t) async {
    await showTaskDetails(context, taskId: t.id, initial: t);
    if (mounted) ref.invalidate(dayViewProvider(_key));
  }

  /// When the task is due on this day: its time, or "All day".
  String _dueText(PlanTask t) {
    final start = t.scheduledStart?.toLocal() ?? t.dueAt?.toLocal();
    return t.allDay || start == null ? 'All day' : 'Due ${hhmm(start)}';
  }

  Widget _taskTile(PlanTask t) {
    final scheme = Theme.of(context).colorScheme;
    final colors = context.tefteri;
    final text = Theme.of(context).textTheme;
    final details = [
      _dueText(t),
      if (t.project != null && t.project!.isNotEmpty) t.project!,
    ].join(' \u00b7 ');
    final note = _syncNote(t.syncState);
    return InkWell(
      key: Key('task-${t.id}'),
      // A tap on the row opens the task to edit it.
      onTap: () => _edit(t),
      child: DecoratedBox(
        // A ruled line under every task, like the lines of a notebook page.
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.rule)),
        ),
        child: Row(
          children: [
            // A large target, so that a finger can hit it.
            IconButton(
              key: Key('complete-${t.id}'),
              tooltip: t.done ? 'Mark not done' : 'Mark done',
              iconSize: 28,
              constraints: const BoxConstraints(minWidth: 52, minHeight: 52),
              icon: Icon(
                t.done ? Icons.check_circle : Icons.radio_button_unchecked,
                color: t.done
                    ? (parseCalendarColor(t.projectColor) ?? colors.task)
                    : scheme.onSurfaceVariant,
              ),
              onPressed: () => _toggle(t),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: t.done ? scheme.onSurfaceVariant : null,
                        decoration: t.done ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    Text(details,
                        key: Key('task-due-${t.id}'), style: text.bodySmall),
                    if (note.isNotEmpty)
                      Text(note.substring(3), style: text.bodySmall),
                  ],
                ),
              ),
            ),
            IconButton(
              key: Key('delete-${t.id}'),
              tooltip: 'Delete task',
              icon: const Icon(Icons.delete_outline),
              onPressed: () =>
                  _run(() => ref.read(planningApiProvider).deleteTask(t.id)),
            ),
          ],
        ),
      ),
    );
  }

  /// Text appended to a subtitle for non-synced items (starts with " - ").
  String _syncNote(String state) => switch (state) {
        'conflict' => ' - Conflict. Open Conflicts to fix it.',
        'deleted_remotely' => ' - Deleted in the other app.',
        _ => '',
      };
}
