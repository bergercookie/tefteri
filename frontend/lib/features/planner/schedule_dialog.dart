/// Dialog to choose a day and a time for a task, used where dragging is not
/// possible (small screens) and by the week, month and year views.
library;

import 'package:flutter/material.dart';

import '../../core/planning_models.dart';
import 'time_grid.dart';

/// Hour used when a task is planned for a day without a chosen time.
const defaultScheduleHour = 9;

/// Lets the user choose a day and a time in 15-minute steps.
///
/// The chosen time is the **start** of the task's one-hour block. The task
/// app stores the due date one hour later.
class ScheduleDialog extends StatefulWidget {
  /// Creates a dialog that offers [days] and starts at [initial].
  const ScheduleDialog({required this.days, required this.initial, super.key});

  /// Days the user can choose.
  final List<DateTime> days;

  /// Initial day and time.
  final DateTime initial;

  @override
  State<ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends State<ScheduleDialog> {
  late DateTime _day;
  late int _minutes;

  @override
  void initState() {
    super.initState();
    final i = widget.initial.toLocal();
    _day = widget.days.firstWhere(
        (d) => d.year == i.year && d.month == i.month && d.day == i.day,
        orElse: () => widget.days.first);
    _minutes = snapMinutes((i.hour * 60 + i.minute).toDouble());
  }

  static String _label(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Choose a time'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButton<DateTime>(
            key: const Key('schedule-day'),
            value: _day,
            items: [
              for (final d in widget.days)
                DropdownMenuItem(value: d, child: Text(dateKey(d))),
            ],
            onChanged: (v) => setState(() => _day = v ?? _day),
          ),
          DropdownButton<int>(
            key: const Key('schedule-time'),
            value: _minutes,
            items: [
              for (var m = 0; m < minutesPerDay; m += slotMinutes)
                DropdownMenuItem(value: m, child: Text(_label(m))),
            ],
            onChanged: (v) => setState(() => _minutes = v ?? _minutes),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('schedule-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('schedule-confirm'),
          onPressed: () => Navigator.of(context).pop(DateTime(
              _day.year, _day.month, _day.day, _minutes ~/ 60, _minutes % 60)),
          child: const Text('Schedule'),
        ),
      ],
    );
  }
}
