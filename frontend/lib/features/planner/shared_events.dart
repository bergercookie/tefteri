/// One event in several calendars, and the text shown on hover of a block.
library;

import '../../core/planning_models.dart';

/// Shows each event once, even when several shown calendars hold a copy.
///
/// The owner of one calendar can see another person's calendar too. When that
/// person invites them to an event, Google keeps one copy of it in each
/// calendar, with the same UID and the same times. Such copies become one item
/// that knows the other calendars ([CalendarItem.alsoIn]). The copy kept is
/// one that the user can change, so it can still be moved. Tasks, and events
/// without a UID, stay as they are. The order of [items] is kept.
List<CalendarItem> mergeSharedEvents(List<CalendarItem> items) {
  final groups = <(String, DateTime?, DateTime?, bool), List<CalendarItem>>{};
  for (final i in items) {
    final uid = i.uid;
    if (i.isTask || uid == null || uid.isEmpty) continue;
    groups.putIfAbsent((uid, i.start, i.end, i.allDay), () => []).add(i);
  }
  final merged = <CalendarItem, CalendarItem>{};
  final dropped = <CalendarItem>{};
  for (final copies in groups.values) {
    // The same event twice in one calendar is not a shared event.
    final calendars = {for (final c in copies) c.containerId};
    if (copies.length < 2 || calendars.length < 2) continue;
    final keep =
        copies.firstWhere((c) => !c.readOnly, orElse: () => copies.first);
    final seen = {keep.containerId};
    final others = [
      for (final c in copies)
        if (seen.add(c.containerId)) c,
    ];
    merged[keep] = keep.withCopies(others);
    dropped.addAll(copies.where((c) => c != keep));
  }
  if (merged.isEmpty) return items;
  return [
    for (final i in items)
      if (!dropped.contains(i)) merged[i] ?? i,
  ];
}

/// `A`, `A and B`, or `A, B and C`.
String _list(List<String> names) => names.length < 2
    ? names.join()
    : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';

/// The line that says which calendars hold [item], or null when none is known.
String? calendarsLine(CalendarItem item) {
  final names = item.calendarNames;
  if (names.isEmpty) return null;
  if (!item.isShared) return 'Calendar: ${names.first}';
  final both = names.length == 2 ? 'both ' : 'all ';
  return 'Available in ${both}calendars ${_list(names)}';
}

/// What the planner shows when the pointer rests on a block: the whole
/// title, the time, and the calendars of an event or the project of a task.
String itemTooltip(CalendarItem item) {
  final start = item.start?.toLocal();
  final end = item.end?.toLocal();
  final when = start == null
      ? null
      : item.allDay
          ? '${dateKey(start)}, all day'
          : item.isTask
              ? 'Due ${dateKey(end ?? start)} ${hhmm(end ?? start)}'
              : '${dateKey(start)}, ${hhmm(start)}'
                  '${end == null ? '' : ' - ${hhmm(end)}'}';
  final calendars = item.isTask ? null : calendarsLine(item);
  return [
    item.title,
    if (when != null) when,
    if (item.isTask && item.project != null) 'Project: ${item.project}',
    if (item.isDone) 'Done',
    if (calendars != null) calendars,
    if (!item.isTask && item.readOnly) 'Read only',
  ].join('\n');
}
