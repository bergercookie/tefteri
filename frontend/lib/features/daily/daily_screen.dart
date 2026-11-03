/// Daily view: entries, tasks and the daily note for one day.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/context_filter.dart';
import '../../core/planning_api.dart';
import '../../core/planning_models.dart';
import '../../core/shell.dart';
import '../settings/connection_models.dart';
import '../settings/sync_controller.dart';
import 'daily_providers.dart';

/// Shows one day with quick add, complete, delete and note append.
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

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate ?? DateTime.now();
  }

  @override
  void dispose() {
    _titleCtl.dispose();
    _noteCtl.dispose();
    super.dispose();
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

  void _today() => setState(() {
        _date = DateTime.now();
        _error = null;
      });

  void _shiftDay(int days) => setState(() {
        _date = DateTime(_date.year, _date.month, _date.day + days);
        _error = null;
      });

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
              loading: () => const Center(child: CircularProgressIndicator()),
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
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        Text('Events', style: theme.titleMedium),
        if (v.entries.isEmpty) const Text('No events.'),
        for (final e in v.entries) _entryTile(e),
        const SizedBox(height: 16),
        Text('Tasks', style: theme.titleMedium),
        if (v.tasks.isEmpty) const Text('No tasks.'),
        for (final t in v.tasks) _taskTile(t),
        const SizedBox(height: 16),
        Text('Daily note', style: theme.titleMedium),
        Text(
          (v.note?.body.isNotEmpty ?? false) ? v.note!.body : 'No note yet.',
          key: const Key('note-body'),
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('note-field'),
                controller: _noteCtl,
                decoration: const InputDecoration(hintText: 'Add to the note'),
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
      ],
    );
  }

  Widget _entryTile(PlanEntry e) {
    final time = e.allDay || e.start == null
        ? 'All day'
        : '${hhmm(e.start!)} - ${e.end == null ? '' : hhmm(e.end!)}';
    final place = (e.location?.isNotEmpty ?? false) ? ' - ${e.location}' : '';
    return ListTile(
      key: Key('entry-${e.id}'),
      leading: const Icon(Icons.event),
      title: Text(e.title),
      subtitle: Text('$time$place${_syncNote(e.syncState)}'),
      trailing: ContextMarker(itemContext: e.context),
    );
  }

  Widget _taskTile(PlanTask t) => ListTile(
        key: Key('task-${t.id}'),
        leading: Checkbox(
          key: Key('complete-${t.id}'),
          value: t.done,
          onChanged: t.done
              ? null
              : (_) =>
                  _run(() => ref.read(planningApiProvider).completeTask(t.id)),
        ),
        title: Text(
          t.title,
          style: t.done
              ? const TextStyle(decoration: TextDecoration.lineThrough)
              : null,
        ),
        subtitle: _syncNote(t.syncState).isEmpty
            ? null
            : Text(_syncNote(t.syncState).substring(3)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ContextMarker(itemContext: t.context),
            IconButton(
              key: Key('delete-${t.id}'),
              tooltip: 'Delete task',
              icon: const Icon(Icons.delete_outline),
              onPressed: () =>
                  _run(() => ref.read(planningApiProvider).deleteTask(t.id)),
            ),
          ],
        ),
      );

  /// Text appended to a subtitle for non-synced items (starts with " - ").
  String _syncNote(String state) => switch (state) {
        'conflict' => ' - Conflict. Open Conflicts to fix it.',
        'deleted_remotely' => ' - Deleted in the other app.',
        _ => '',
      };
}
