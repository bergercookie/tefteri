/// Layout maths of the planner's time grid. Pure functions, no widgets.
library;

/// Height in logical pixels of one hour in the time grid.
const double hourHeight = 56;

/// Minutes in one grid slot. Drops snap to the start of a slot.
const int slotMinutes = 15;

/// Minutes in a day.
const int minutesPerDay = 24 * 60;

/// Converts a vertical offset inside a day column to minutes after midnight.
double offsetToMinutes(double dy, {double hour = hourHeight}) => dy / hour * 60;

/// Converts minutes after midnight to a vertical offset in a day column.
double minutesToOffset(num minutes, {double hour = hourHeight}) =>
    minutes / 60 * hour;

/// Snaps [minutes] down to the start of its 15-minute slot, inside the day.
int snapMinutes(double minutes) {
  final slot = (minutes / slotMinutes).floor() * slotMinutes;
  return slot.clamp(0, minutesPerDay - slotMinutes);
}

/// The local start time of the slot under vertical offset [dy] on [day].
DateTime slotStart(DateTime day, double dy, {double hour = hourHeight}) {
  final m = snapMinutes(offsetToMinutes(dy, hour: hour));
  return DateTime(day.year, day.month, day.day, m ~/ 60, m % 60);
}

/// Where one block sits among overlapping blocks: [column] of [columns].
class BlockColumn {
  /// Creates a placement.
  const BlockColumn(this.index, this.column, this.columns);

  /// Index of the block in the list given to [layoutOverlaps].
  final int index;

  /// Zero-based column of the block inside its group of overlapping blocks.
  final int column;

  /// Number of columns in that group.
  final int columns;
}

/// Places blocks side by side when they overlap.
///
/// Each span is `(startMinute, endMinute)`. Spans that only touch do not
/// overlap. Returns one [BlockColumn] per span, in the order of the input.
List<BlockColumn> layoutOverlaps(List<(int, int)> spans) {
  final order = [for (var i = 0; i < spans.length; i++) i]..sort((a, b) {
      final c = spans[a].$1.compareTo(spans[b].$1);
      return c != 0 ? c : spans[a].$2.compareTo(spans[b].$2);
    });
  final result = List<BlockColumn?>.filled(spans.length, null);
  var group = <int>[];
  var groupEnd = -1;
  final columnEnds = <int>[];
  final columnOf = <int, int>{};

  void flush() {
    for (final i in group) {
      result[i] = BlockColumn(i, columnOf[i]!, columnEnds.length);
    }
    group = [];
    columnEnds.clear();
  }

  for (final i in order) {
    final (start, end) = spans[i];
    if (group.isNotEmpty && start >= groupEnd) flush();
    var column = columnEnds.indexWhere((e) => e <= start);
    if (column == -1) {
      columnEnds.add(end);
      column = columnEnds.length - 1;
    } else {
      columnEnds[column] = end;
    }
    columnOf[i] = column;
    group.add(i);
    groupEnd = group.length == 1 ? end : (end > groupEnd ? end : groupEnd);
  }
  flush();
  return [for (final r in result) r!];
}
