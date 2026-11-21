/// The menu of a right click on an empty slot of the calendar, and the pop-up
/// that adds an event to a calendar.
///
/// Shift+N opens the pop-up on every page. The day, the time and the length are
/// text fields that take typed input (`YYYYMMDD`, `YYYYMMDDTHHmm`, `HHmm`,
/// `1h30`), and each has a button for a picker.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/calendar_color.dart';
import '../../core/event_calendars.dart';
import '../../core/event_input.dart';
import '../../core/planning_api.dart';
import '../../core/planning_models.dart';
import '../../theme/theme.dart';
import '../settings/planner_settings_card.dart';
import 'new_task_dialog.dart';
import 'planner_providers.dart';

export '../../core/event_calendars.dart';

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

/// Lengths that the button next to the length field offers.
const List<Duration> eventLengthPresets = [
  Duration(minutes: 15),
  Duration(minutes: 30),
  Duration(minutes: 45),
  Duration(hours: 1),
  Duration(minutes: 90),
  Duration(hours: 2),
  Duration(hours: 3),
  Duration(hours: 4),
];

/// Adds an event to one of the calendars of the user. The user gives the
/// title, the calendar, the day, the start time and the length (or all day)
/// and a place.
class NewEventDialog extends ConsumerStatefulWidget {
  /// Creates the pop-up. The event starts at [start]; [allDay] starts it as an
  /// all-day event.
  const NewEventDialog({required this.start, this.allDay = false, super.key});

  /// Where the user clicked, or the next full hour.
  final DateTime start;

  /// The event starts as an all-day event.
  final bool allDay;

  @override
  ConsumerState<NewEventDialog> createState() => _NewEventDialogState();
}

class _NewEventDialogState extends ConsumerState<NewEventDialog> {
  final _title = TextEditingController();
  final _location = TextEditingController();
  late final _day = TextEditingController(text: formatDay(widget.start));
  late final _time = TextEditingController(
      text: formatTime(TimeOfDay.fromDateTime(widget.start)));
  final _length = TextEditingController(text: '1h');
  EventCalendar? _calendar;

  /// The standard invitees that the user ticked. Nobody is ticked at first: an
  /// invitation is sent to a person, so the user picks each one.
  final Set<String> _invited = {};
  late bool _allDay = widget.allDay;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _day.dispose();
    _time.dispose();
    _length.dispose();
    super.dispose();
  }

  DateTime? get _dayValue => parseDay(_day.text);

  TimeOfDay? get _timeValue => parseTime(_time.text);

  Duration? get _lengthValue => parseEventLength(_length.text);

  bool get _inputOk =>
      _dayValue != null &&
      (_allDay || (_timeValue != null && _lengthValue != null));

  bool get _canCreate =>
      !_busy && _calendar != null && _title.text.trim().isNotEmpty && _inputOk;

  /// The start of the event, or null while the input is not valid.
  DateTime? get _startValue {
    final d = _dayValue;
    final t = _allDay ? const TimeOfDay(hour: 0, minute: 0) : _timeValue;
    return d == null || t == null
        ? null
        : DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  void _set(TextEditingController c, String text) => c.value = TextEditingValue(
      text: text, selection: TextSelection.collapsed(offset: text.length));

  /// A full `YYYYMMDDTHHmm` in the day or the time field sets both fields.
  void _typed(String text) {
    final p = parseDayAndTime(text);
    if (p != null && p.time != null) {
      _set(_day, formatDay(p.day));
      _set(_time, formatTime(p.time!));
    }
    setState(() {});
  }

  /// Writes a valid value of [c] in the standard form when the user leaves it.
  void _tidy(TextEditingController c, String? Function() standard) {
    final text = standard();
    if (text != null && text != c.text) _set(c, text);
    if (mounted) setState(() {});
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dayValue ?? widget.start,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() => _set(_day, formatDay(picked)));
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
        context: context,
        initialTime: _timeValue ?? TimeOfDay.fromDateTime(widget.start),
        // Times are 24 hours everywhere in tefteri: no AM or PM.
        builder: (context, child) => MediaQuery(
              data:
                  MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
              child: child!,
            ));
    if (picked != null && mounted) {
      setState(() => _set(_time, formatTime(picked)));
    }
  }

  Future<void> _create() async {
    final calendar = _calendar;
    final from = _startValue;
    if (calendar == null || from == null || !_canCreate) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final actions = ref.read(plannerActionsProvider);
    final remember = ref.read(lastEventCalendarProvider.notifier);
    final day = _dayValue!;
    final start = _allDay ? DateTime(day.year, day.month, day.day) : from;
    final end = _allDay
        ? DateTime(day.year, day.month, day.day + 1)
        : start.add(_lengthValue!);
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
        attendees: [
          for (final a
              in ref.read(userSettingsProvider).valueOrNull?.eventInvitees ??
                  const <String>[])
            if (_invited.contains(a)) a,
        ],
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

  /// A text field for typed input, with a button that opens a picker.
  Widget _typedField({
    required String name,
    required TextEditingController controller,
    required String label,
    required String hint,
    required String? Function() standard,
    required bool valid,
    required String problem,
    required IconData icon,
    required String pickTooltip,
    required VoidCallback onPick,
    ValueChanged<String>? onChanged,
  }) {
    return Focus(
      // Only to hear when the field loses the focus: it is not a stop of its own
      // when the user presses Tab.
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) {
        if (!focused) _tidy(controller, standard);
      },
      child: TextField(
        key: Key('new-event-$name'),
        controller: controller,
        enabled: !_busy,
        keyboardType: TextInputType.datetime,
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          errorText: valid ? null : problem,
          // The picker is for the mouse. Tab goes from field to field, so the
          // button is out of the tab order.
          suffixIcon: ExcludeFocus(
            child: IconButton(
              key: Key('new-event-$name-pick'),
              tooltip: pickTooltip,
              visualDensity: VisualDensity.compact,
              icon: Icon(icon, size: 18),
              onPressed: _busy ? null : onPick,
            ),
          ),
        ),
        onChanged: onChanged ?? (_) => setState(() {}),
        onSubmitted: (_) => _tidy(controller, standard),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final calendars = ref.watch(eventCalendarsProvider);
    final settings = ref.watch(userSettingsProvider);
    final remembered = ref.watch(lastEventCalendarProvider);
    final wanted = settings.valueOrNull?.defaultEventContainerId;
    final list = calendars.valueOrNull ?? const <EventCalendar>[];
    // Start in the calendar that the user chose in the settings, else in the
    // calendar of the last event, else in the first one. Wait for the settings
    // so that the choice does not jump when they arrive.
    if (_calendar == null && !settings.isLoading && list.isNotEmpty) {
      EventCalendar? named(String? id) =>
          list.where((c) => c.containerId == id).firstOrNull;
      _calendar = named(wanted) ?? named(remembered) ?? list.first;
    }
    final width =
        440.0.clamp(0, MediaQuery.sizeOf(context).width - 96).toDouble();
    final start = _startValue;
    final length = _lengthValue;
    final end = start != null && length != null ? start.add(length) : null;
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
                _calendarPicker(calendars, settings, list),
                const SizedBox(height: Space.md),
                _typedField(
                  name: 'date',
                  controller: _day,
                  label: 'Day',
                  hint: 'YYYYMMDD',
                  standard: () {
                    final d = _dayValue;
                    return d == null ? null : formatDay(d);
                  },
                  valid: _dayValue != null,
                  problem: 'Type the day as YYYYMMDD',
                  icon: Icons.calendar_today_outlined,
                  pickTooltip: 'Pick a day',
                  onPick: _pickDate,
                  // YYYYMMDDTHHmm here sets the time too.
                  onChanged: _typed,
                ),
                SwitchListTile(
                  key: const Key('new-event-all-day'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('All day'),
                  value: _allDay,
                  onChanged: _busy ? null : (v) => setState(() => _allDay = v),
                ),
                if (!_allDay) ...[
                  _typedField(
                    name: 'start',
                    controller: _time,
                    label: 'Starts at',
                    hint: 'HHmm',
                    standard: () {
                      final t = _timeValue;
                      return t == null ? null : formatTime(t);
                    },
                    valid: _timeValue != null,
                    problem: 'Type the time as HHmm',
                    icon: Icons.schedule_outlined,
                    pickTooltip: 'Pick a time',
                    onPick: _pickTime,
                    // YYYYMMDDTHHmm here sets the day too.
                    onChanged: _typed,
                  ),
                  const SizedBox(height: Space.md),
                  _typedField(
                    name: 'length',
                    controller: _length,
                    label: 'Length',
                    hint: '1h30',
                    standard: () {
                      final d = _lengthValue;
                      return d == null ? null : formatEventLength(d);
                    },
                    valid: _lengthValue != null,
                    problem: 'Type minutes or hours, such as 45m or 1h30',
                    icon: Icons.timer_outlined,
                    pickTooltip: 'Choose a length',
                    onPick: _chooseLength,
                  ),
                  if (end != null)
                    Padding(
                      padding: const EdgeInsets.only(top: Space.xs),
                      child: Text('Ends ${formatDay(end)} ${hhmm(end)}',
                          key: const Key('new-event-ends'),
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                ],
                const SizedBox(height: Space.md),
                TextField(
                  key: const Key('new-event-location'),
                  controller: _location,
                  enabled: !_busy,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Place'),
                ),
                _invitees(),
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

  /// The people that the user usually invites, one tick box for each. Tab
  /// moves to a box and Space ticks it.
  Widget _invitees() {
    final text = Theme.of(context).textTheme;
    final people = ref.watch(userSettingsProvider).valueOrNull?.eventInvitees ??
        const <String>[];
    return Padding(
      padding: const EdgeInsets.only(top: Space.md),
      child: Column(
        key: const Key('new-event-invitees'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Invite', style: text.labelLarge),
          if (people.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text(
                'No standard invitees yet. Add the people that you often '
                'invite in Settings.',
                key: const Key('new-event-no-invitees'),
                style: text.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            )
          else
            for (final a in people)
              CheckboxListTile(
                key: Key('new-event-invitee-$a'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(a),
                value: _invited.contains(a),
                onChanged: _busy
                    ? null
                    : (v) => setState(
                        () => v == true ? _invited.add(a) : _invited.remove(a)),
              ),
          if (_invited.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text(
                _invited.length == 1
                    ? 'The calendar app sends an invitation to 1 person.'
                    : 'The calendar app sends an invitation to '
                        '${_invited.length} people.',
                key: const Key('new-event-invite-note'),
                style: text.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  /// The "pick" button of the length field opens a menu of common lengths.
  Future<void> _chooseLength() async {
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final centre = box.localToGlobal(box.size.center(Offset.zero));
    final picked = await showMenu<Duration>(
      context: context,
      position: RelativeRect.fromRect(Rect.fromLTWH(centre.dx, centre.dy, 1, 1),
          Offset.zero & overlay.size),
      items: [
        for (final d in eventLengthPresets)
          PopupMenuItem(
            key: Key('new-event-length-${formatEventLength(d)}'),
            value: d,
            child: Text(formatEventLength(d)),
          ),
      ],
    );
    if (picked != null && mounted) {
      setState(() => _set(_length, formatEventLength(picked)));
    }
  }

  Widget _calendarPicker(AsyncValue<List<EventCalendar>> calendars,
      AsyncValue<Object?> settings, List<EventCalendar> list) {
    final text = Theme.of(context).textTheme;
    if (calendars.isLoading || settings.isLoading) {
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
