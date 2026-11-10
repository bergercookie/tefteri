/// The menu of a right click on an empty slot of the calendar, and the pop-up
/// that adds an event to a calendar.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/api_error.dart';
import '../../core/calendar_color.dart';
import '../../core/planning_api.dart';
import '../../core/planning_models.dart';
import '../../theme/theme.dart';
import 'new_task_dialog.dart';
import 'picker_field.dart';
import 'planner_providers.dart';

/// A calendar that a new event can go into: it is on, and the user can change
/// what it holds.
class EventCalendar {
  /// Creates a calendar.
  const EventCalendar({
    required this.connectionId,
    required this.connectionName,
    required this.containerId,
    required this.name,
    this.color,
  });

  /// Id of the connection that holds the calendar.
  final String connectionId;

  /// Name of that connection (a Google account).
  final String connectionName;

  /// Id of the calendar in tefteri.
  final String containerId;

  /// Name of the calendar.
  final String name;

  /// Its color in the calendar app (`#rrggbb`), or null.
  final String? color;
}

/// Every calendar of every calendar connection that is on and not read-only.
final eventCalendarsProvider = FutureProvider<List<EventCalendar>>((ref) async {
  final dio = ref.watch(dioProvider);
  Future<List<Map<String, dynamic>>> list(String path) async {
    final r = await dio.get<Object?>(path);
    return [
      for (final e in (r.data as List? ?? const []))
        if (e is Map<String, dynamic>) e,
    ];
  }

  final out = <EventCalendar>[];
  for (final c in await list('/connections')) {
    if (c['kind'] != 'calendar') continue;
    final id = '${c['id']}';
    for (final p in await list('/connections/$id/containers')) {
      if (p['enabled'] == false || p['read_only'] == true) continue;
      out.add(EventCalendar(
        connectionId: id,
        connectionName: '${c['display_name']}',
        containerId: '${p['id']}',
        name: '${p['name']}',
        color: p['color'] as String?,
      ));
    }
  }
  out.sort((a, b) {
    final byConnection = a.connectionName.compareTo(b.connectionName);
    return byConnection != 0
        ? byConnection
        : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return out;
});

/// The calendar of the last new event. The next one starts there.
final lastEventCalendarProvider = StateProvider<String?>((_) => null);

/// Opens the menu of a right click at [at] on an empty slot that starts at
/// [start]. [allDay] is true for the all-day row. The menu offers a new event
/// and a new task, and opens the pop-up of the one that the user picks.
Future<void> showSlotMenu(
  BuildContext context,
  Offset at, {
  required DateTime start,
  bool allDay = false,
}) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (overlay == null) return;
  final when = allDay ? 'on ${dateKey(start)}' : 'at ${hhmm(start)}';
  final choice = await showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(
        Rect.fromLTWH(at.dx, at.dy, 1, 1), Offset.zero & overlay.size),
    items: [
      PopupMenuItem(
        key: const Key('slot-new-event'),
        value: 'event',
        child: _MenuRow(Icons.event_outlined, 'New event $when'),
      ),
      PopupMenuItem(
        key: const Key('slot-new-task'),
        value: 'task',
        child: _MenuRow(Icons.add_task_outlined, 'New task $when'),
      ),
    ],
  );
  if (choice == null || !context.mounted) return;
  if (choice == 'event') {
    await showNewEventDialog(context, start: start, allDay: allDay);
  } else {
    await showNewTaskDialog(context, start: start, allDay: allDay);
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: Space.sm),
          Flexible(child: Text(text, overflow: TextOverflow.ellipsis)),
        ],
      );
}

/// Opens the pop-up that adds an event that starts at [start].
Future<void> showNewEventDialog(BuildContext context,
        {required DateTime start, bool allDay = false}) =>
    showDialog<void>(
      context: context,
      builder: (_) => NewEventDialog(start: start, allDay: allDay),
    );

/// Adds an event to one of the calendars of the user. The user gives the
/// title, the calendar, the day, the times (or all day) and a place.
class NewEventDialog extends ConsumerStatefulWidget {
  /// Creates the pop-up. The event starts at [start]; [allDay] starts it as an
  /// all-day event.
  const NewEventDialog({required this.start, this.allDay = false, super.key});

  /// Where the user clicked.
  final DateTime start;

  /// The event starts as an all-day event.
  final bool allDay;

  @override
  ConsumerState<NewEventDialog> createState() => _NewEventDialogState();
}

class _NewEventDialogState extends ConsumerState<NewEventDialog> {
  final _title = TextEditingController();
  final _location = TextEditingController();
  EventCalendar? _calendar;
  late DateTime _date =
      DateTime(widget.start.year, widget.start.month, widget.start.day);
  late TimeOfDay _from = TimeOfDay.fromDateTime(widget.start);
  late TimeOfDay _to = _after(_from);
  late bool _allDay = widget.allDay;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    super.dispose();
  }

  /// One hour after [t], but not after the end of the day.
  static TimeOfDay _after(TimeOfDay t) => t.hour >= 23
      ? const TimeOfDay(hour: 23, minute: 59)
      : TimeOfDay(hour: t.hour + 1, minute: t.minute);

  static int _minutes(TimeOfDay t) => t.hour * 60 + t.minute;

  static String _hm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  bool get _timesOk => _allDay || _minutes(_to) > _minutes(_from);

  bool get _canCreate =>
      !_busy && _calendar != null && _title.text.trim().isNotEmpty && _timesOk;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() => _date = DateTime(picked.year, picked.month, picked.day));
    }
  }

  Future<void> _pickFrom() async {
    final picked = await showTimePicker(context: context, initialTime: _from);
    if (picked == null || !mounted) return;
    setState(() {
      // Keep the length of the event when the start moves.
      final length = _minutes(_to) - _minutes(_from);
      _from = picked;
      final end = _minutes(picked) + (length > 0 ? length : 60);
      _to = end >= 24 * 60
          ? const TimeOfDay(hour: 23, minute: 59)
          : TimeOfDay(hour: end ~/ 60, minute: end % 60);
    });
  }

  Future<void> _pickTo() async {
    final picked = await showTimePicker(context: context, initialTime: _to);
    if (picked != null && mounted) setState(() => _to = picked);
  }

  Future<void> _create() async {
    final calendar = _calendar;
    if (calendar == null || !_canCreate) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final actions = ref.read(plannerActionsProvider);
    final remember = ref.read(lastEventCalendarProvider.notifier);
    final DateTime start;
    final DateTime end;
    if (_allDay) {
      start = _date;
      end = DateTime(_date.year, _date.month, _date.day + 1);
    } else {
      start = DateTime(
          _date.year, _date.month, _date.day, _from.hour, _from.minute);
      end = DateTime(_date.year, _date.month, _date.day, _to.hour, _to.minute);
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(planningApiProvider).createEntry(
            connectionId: calendar.connectionId,
            containerId: calendar.containerId,
            title: _title.text.trim(),
            start: start,
            end: end,
            allDay: _allDay,
            location: _location.text.trim(),
          );
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = apiErrorMessage(e);
        });
      }
      return;
    }
    remember.state = calendar.containerId;
    actions.refresh();
    messenger.showSnackBar(SnackBar(
      key: const Key('new-event-created'),
      content: Text('Event added to ${calendar.name}.'),
    ));
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final calendars = ref.watch(eventCalendarsProvider);
    final remembered = ref.watch(lastEventCalendarProvider);
    final list = calendars.valueOrNull ?? const <EventCalendar>[];
    // Start in the calendar of the last event, else in the first one.
    _calendar ??= list.isEmpty
        ? null
        : list.firstWhere((c) => c.containerId == remembered,
            orElse: () => list.first);
    final width =
        440.0.clamp(0, MediaQuery.sizeOf(context).width - 96).toDouble();
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () {
          if (_canCreate) _create();
        },
      },
      child: AlertDialog(
        key: const Key('new-event-dialog'),
        title: const Text('New event'),
        content: SizedBox(
          width: width,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.sm),
                    child: Text(_error!,
                        key: const Key('new-event-error'),
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ),
                TextField(
                  key: const Key('new-event-title'),
                  controller: _title,
                  autofocus: true,
                  enabled: !_busy,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Title'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: Space.md),
                _calendarPicker(calendars, list),
                const SizedBox(height: Space.md),
                PickerField(
                  fieldKey: const ValueKey('new-event-date'),
                  clearKey: const Key('new-event-date-clear'),
                  label: 'Day',
                  value: dateKey(_date),
                  empty: 'No date',
                  onTap: _busy ? null : _pickDate,
                  onClear: null,
                ),
                SwitchListTile(
                  key: const Key('new-event-all-day'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('All day'),
                  value: _allDay,
                  onChanged: _busy ? null : (v) => setState(() => _allDay = v),
                ),
                if (!_allDay)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: PickerField(
                          fieldKey: const ValueKey('new-event-start'),
                          clearKey: const Key('new-event-start-clear'),
                          label: 'Starts at',
                          value: _hm(_from),
                          empty: '-',
                          onTap: _busy ? null : _pickFrom,
                          onClear: null,
                        ),
                      ),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: PickerField(
                          fieldKey: const ValueKey('new-event-end'),
                          clearKey: const Key('new-event-end-clear'),
                          label: 'Ends at',
                          value: _hm(_to),
                          empty: '-',
                          onTap: _busy ? null : _pickTo,
                          onClear: null,
                        ),
                      ),
                    ],
                  ),
                if (!_timesOk)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.xs),
                    child: Text('The event must end after it starts.',
                        key: const Key('new-event-times-error'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.error)),
                  ),
                const SizedBox(height: Space.md),
                TextField(
                  key: const Key('new-event-location'),
                  controller: _location,
                  enabled: !_busy,
                  decoration: const InputDecoration(labelText: 'Place'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const Key('new-event-cancel'),
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('new-event-create'),
            onPressed: _canCreate ? _create : null,
            child: Text(_busy ? 'Adding...' : 'Add event'),
          ),
        ],
      ),
    );
  }

  Widget _calendarPicker(
      AsyncValue<List<EventCalendar>> calendars, List<EventCalendar> list) {
    final text = Theme.of(context).textTheme;
    if (calendars.isLoading) {
      return const SizedBox(
          height: 48, child: Center(child: LinearProgressIndicator()));
    }
    if (calendars.hasError) {
      return Text(apiErrorMessage(calendars.error!),
          key: const Key('new-event-calendars-error'));
    }
    if (list.isEmpty) {
      return Text(
        'There is no calendar to add the event to. Connect a Google '
        'calendar in Settings, and choose a calendar that you can change.',
        key: const Key('new-event-no-calendar'),
        style: text.bodyMedium,
      );
    }
    final many = list.map((c) => c.connectionName).toSet().length > 1;
    return DropdownButtonFormField<String>(
      key: const Key('new-event-calendar'),
      initialValue: _calendar?.containerId,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Calendar'),
      items: [
        for (final c in list)
          DropdownMenuItem(
            value: c.containerId,
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: parseCalendarColor(c.color) ??
                        Theme.of(context).colorScheme.outline,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: Space.sm),
                Flexible(
                  child: Text(many ? '${c.name} (${c.connectionName})' : c.name,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
      ],
      onChanged: _busy
          ? null
          : (v) => setState(
              () => _calendar = list.firstWhere((c) => c.containerId == v)),
    );
  }
}
