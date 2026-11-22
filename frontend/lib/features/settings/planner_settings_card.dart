/// Planner settings: what happens when a task is dropped on a day without a
/// time, how long before a task or an event a reminder is sent, and the
/// calendar that a new event starts in.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/event_calendars.dart';
import '../../core/planning_api.dart';
import '../../core/planning_models.dart';
import '../../core/reminder_text.dart';

/// Loads the signed-in user's planning settings.
final userSettingsProvider = FutureProvider<UserSettings>(
    (ref) => ref.watch(planningApiProvider).settings());

/// Widest the settings card gets, in logical pixels.
const double plannerSettingsCardWidth = 560;

/// Offsets the reminder setting offers, in minutes. The current value is
/// listed too when it is not one of them.
const List<int> reminderOffsets = [0, 5, 10, 15, 30, 60, 120, 1440, 2880];

/// A switch for `random_time_on_date_drop`. Off by default: a drop on the
/// all-day row sets a due date only. On: it also picks a random time.
class PlannerSettingsCard extends ConsumerWidget {
  /// Creates the card.
  const PlannerSettingsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(userSettingsProvider);
    // A wide window would stretch the switch far away from its text, so the
    // card keeps a readable width and sits at the left edge.
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: plannerSettingsCardWidth),
        child: _card(context, ref, settings),
      ),
    );
  }

  /// Runs a save, shows the server's message when it fails, and reloads.
  Future<void> _save(BuildContext context, WidgetRef ref,
      Future<Object?> Function() save) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await save();
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
    ref.invalidate(userSettingsProvider);
  }

  /// A choice of how long before the time of something a reminder is sent.
  Widget _reminderSelect(
    BuildContext context,
    WidgetRef ref, {
    required Key selectKey,
    required String title,
    required String subtitle,
    required int value,
    required Future<Object?> Function(int minutes) save,
  }) =>
      ListTile(
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: DropdownButton<int>(
          key: selectKey,
          value: value,
          style: Theme.of(context).textTheme.bodyMedium,
          items: [
            for (final m in {...reminderOffsets, value}.toList()..sort())
              DropdownMenuItem(
                value: m,
                child: Text(m == 0 ? 'At the time' : reminderOffsetText(m)),
              ),
          ],
          onChanged: (m) {
            if (m == null || m == value) return;
            _save(context, ref, () => save(m));
          },
        ),
      );

  /// The choice of the calendar that Shift+N and the new event pop-up start in.
  Widget _eventCalendar(BuildContext context, WidgetRef ref, UserSettings s) {
    final calendars = ref.watch(eventCalendarsProvider);
    final list = calendars.valueOrNull ?? const <EventCalendar>[];
    final chosen = s.defaultEventContainerId;
    // A calendar that is off or read-only is not offered, so the choice falls
    // back to "last used" on screen until the user picks another.
    final value = list.any((c) => c.containerId == chosen) ? chosen : null;
    final many = list.map((c) => c.connectionName).toSet().length > 1;
    return ListTile(
      title: const Text('Calendar for new events'),
      subtitle: Text(calendars.hasError
          ? apiErrorMessage(calendars.error!)
          : 'The calendar that the new event pop-up (Shift+N) starts in. '
              'Without a choice it starts in the calendar of your last event.'),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 200),
        child: DropdownButton<String?>(
          key: const Key('default-event-calendar-select'),
          value: value,
          isExpanded: true,
          style: Theme.of(context).textTheme.bodyMedium,
          items: [
            const DropdownMenuItem<String?>(
                value: null, child: Text('Last used')),
            for (final c in list)
              DropdownMenuItem<String?>(
                value: c.containerId,
                child: Text(many ? '${c.name} (${c.connectionName})' : c.name,
                    overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (id) {
            if (id == value) return;
            _save(
                context,
                ref,
                () => ref
                    .read(planningApiProvider)
                    .updateSettings(defaultEventCalendar: (id: id)));
          },
        ),
      ),
    );
  }

  Widget _card(
      BuildContext context, WidgetRef ref, AsyncValue<UserSettings> settings) {
    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: settings.when(
        loading: () => const ListTile(title: Text('Loading planner settings')),
        error: (e, _) => ListTile(
          key: const Key('planner-settings-error'),
          title: Text(apiErrorMessage(e)),
          trailing: TextButton(
            onPressed: () => ref.invalidate(userSettingsProvider),
            child: const Text('Try again'),
          ),
        ),
        data: (s) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              key: const Key('random-time-switch'),
              title: const Text('Give a random time to date-only drops'),
              subtitle: const Text(
                  'Off: a task dropped on a day without a time gets a due '
                  'date only. On: it also gets a random time between 08:00 '
                  'and 20:00.'),
              value: s.randomTimeOnDateDrop,
              onChanged: (v) => _save(
                  context,
                  ref,
                  () => ref
                      .read(planningApiProvider)
                      .updateSettings(randomTimeOnDateDrop: v)),
            ),
            _reminderSelect(
              context,
              ref,
              selectKey: const Key('default-reminder-select'),
              title: 'Remind me of a task',
              subtitle: 'How long before a task is due that the app sends '
                  'a notification. It does not matter whether the task has '
                  'a reminder in Vikunja. This time is also used when you '
                  'add a reminder to a task.',
              value: s.defaultReminderMinutes,
              save: (m) => ref
                  .read(planningApiProvider)
                  .updateSettings(defaultReminderMinutes: m),
            ),
            _reminderSelect(
              context,
              ref,
              selectKey: const Key('event-reminder-select'),
              title: 'Remind me of an event',
              subtitle: 'How long before a calendar event starts that the '
                  'app sends a notification. An event that is in more than '
                  'one calendar gets one notification.',
              value: s.eventReminderMinutes,
              save: (m) => ref
                  .read(planningApiProvider)
                  .updateSettings(eventReminderMinutes: m),
            ),
            _eventCalendar(context, ref, s),
            _Invitees(
                settings: s,
                save: (list) => _save(
                    context,
                    ref,
                    () => ref
                        .read(planningApiProvider)
                        .updateSettings(eventInvitees: list))),
          ],
        ),
      ),
    );
  }
}

/// The people that the user usually invites to an event: a list with a field
/// to add one. Enter adds the address that is typed.
class _Invitees extends StatefulWidget {
  const _Invitees({required this.settings, required this.save});

  final UserSettings settings;

  /// Saves the whole new list.
  final Future<void> Function(List<String> list) save;

  @override
  State<_Invitees> createState() => _InviteesState();
}

class _InviteesState extends State<_Invitees> {
  final _field = TextEditingController();
  String? _problem;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  static final _address = RegExp(r'^[^@\s,;<>]+@[^@\s,;<>]+\.[^@\s,;<>]+$');

  Future<void> _add() async {
    final text = _field.text.trim();
    if (text.isEmpty) return;
    if (!_address.hasMatch(text)) {
      setState(
          () => _problem = 'Type an e-mail address, such as sam@example.com');
      return;
    }
    final list = widget.settings.eventInvitees;
    setState(() => _problem = null);
    _field.clear();
    if (list.any((a) => a.toLowerCase() == text.toLowerCase())) return;
    await widget.save([...list, text]);
  }

  @override
  Widget build(BuildContext context) {
    final people = widget.settings.eventInvitees;
    final text = Theme.of(context).textTheme;
    return Padding(
      key: const Key('invitees-setting'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('People you invite to events', style: text.titleMedium),
          const SizedBox(height: 4),
          Text(
            'The new event pop-up lists these people, so you can invite them '
            'with a tick. The calendar app sends the invitation.',
            style: text.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          if (people.isEmpty)
            Text('Nobody yet.',
                key: const Key('invitees-empty'), style: text.bodyMedium)
          else
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final a in people)
                  InputChip(
                    key: Key('invitee-$a'),
                    label: Text(a),
                    deleteButtonTooltipMessage: 'Remove $a',
                    onDeleted: () => widget.save([
                      for (final b in people)
                        if (b != a) b
                    ]),
                  ),
              ],
            ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('invitee-field'),
            controller: _field,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'Add a person',
              hintText: 'sam@example.com',
              errorText: _problem,
              suffixIcon: IconButton(
                key: const Key('invitee-add'),
                tooltip: 'Add',
                icon: const Icon(Icons.add),
                onPressed: _add,
              ),
            ),
            onChanged: (_) {
              if (_problem != null) setState(() => _problem = null);
            },
            onSubmitted: (_) => _add(),
          ),
        ],
      ),
    );
  }
}
