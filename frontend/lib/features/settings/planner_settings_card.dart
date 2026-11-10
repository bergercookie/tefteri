/// Planner settings: what happens when a task is dropped on a day without a
/// time, and how long before its due time a task reminder fires.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
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
          ],
        ),
      ),
    );
  }
}
