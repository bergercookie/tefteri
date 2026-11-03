import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/planner/time_grid.dart';

void main() {
  test('offset and minutes convert both ways', () {
    expect(offsetToMinutes(hourHeight * 2), 120);
    expect(minutesToOffset(90), hourHeight * 1.5);
    expect(offsetToMinutes(minutesToOffset(37)), closeTo(37, 1e-9));
  });

  test('snapMinutes floors to the 15-minute slot and stays in the day', () {
    expect(snapMinutes(0), 0);
    expect(snapMinutes(14.9), 0);
    expect(snapMinutes(15), 15);
    expect(snapMinutes(14 * 60 + 29.9), 14 * 60 + 15);
    expect(snapMinutes(-5), 0);
    expect(snapMinutes(minutesPerDay + 100.0), minutesPerDay - slotMinutes);
  });

  test('slotStart gives the local start of the slot under the pointer', () {
    final day = DateTime(2026, 11, 4);
    expect(slotStart(day, 0), DateTime(2026, 11, 4));
    expect(slotStart(day, minutesToOffset(14 * 60 + 40)),
        DateTime(2026, 11, 4, 14, 30));
    expect(slotStart(day, minutesToOffset(23 * 60 + 59)),
        DateTime(2026, 11, 4, 23, 45));
  });

  test('blocks that do not overlap share no columns', () {
    final l = layoutOverlaps([(60, 120), (120, 180), (200, 260)]);
    expect(
        [for (final b in l) (b.column, b.columns)], [(0, 1), (0, 1), (0, 1)]);
  });

  test('two overlapping blocks sit side by side', () {
    final l = layoutOverlaps([(60, 120), (90, 150)]);
    expect([for (final b in l) (b.column, b.columns)], [(0, 2), (1, 2)]);
  });

  test('a free column is reused inside a group', () {
    // 0: 0-100, 1: 10-50 (column 1), 2: 60-90 (column 1 again, 1 ended)
    final l = layoutOverlaps([(0, 100), (10, 50), (60, 90)]);
    expect(
        [for (final b in l) (b.column, b.columns)], [(0, 2), (1, 2), (1, 2)]);
  });

  test('results keep the input order and groups are independent', () {
    final l = layoutOverlaps([(300, 360), (0, 60), (30, 90), (310, 330)]);
    expect([for (final b in l) b.index], [0, 1, 2, 3]);
    expect([for (final b in l) (b.column, b.columns)],
        [(0, 2), (0, 2), (1, 2), (1, 2)]);
  });

  test('identical spans get their own columns', () {
    final l = layoutOverlaps([(60, 120), (60, 120), (60, 120)]);
    expect({for (final b in l) b.column}, {0, 1, 2});
    expect(l.every((b) => b.columns == 3), isTrue);
  });
}
