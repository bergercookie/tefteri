/// Planner settings: what happens when a task is dropped on a day without a
/// time, how long before its due time a task reminder fires, and the calendar
/// that a new event starts in.
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
            ListTile(
              title: const Text('Default reminder'),
              subtitle: const Text(
                  'How long before its due time a reminder fires when you '
                  'add one to a task. Reminders are kept in Vikunja.'),
              trailing: DropdownButton<int>(
                key: const Key('default-reminder-select'),
                value: s.defaultReminderMinutes,
                style: Theme.of(context).textTheme.bodyMedium,
                items: [
                  for (final m
                      in {...reminderOffsets, s.defaultReminderMinutes}.toList()
                        ..sort())
                    DropdownMenuItem(
                      value: m,
                      child: Text(
                          m == 0 ? 'At the due time' : reminderOffsetText(m)),
                    ),
                ],
                onChanged: (m) {
                  if (m == null || m == s.defaultReminderMinutes) return;
                  _save(
                      context,
                      ref,
                      () => ref
                          .read(planningApiProvider)
                          .updateSettings(defaultReminderMinutes: m));
                },
              ),
            ),
            _eventCalendar(context, ref, s),
          ],
        ),
      ),
    );
  }
}
