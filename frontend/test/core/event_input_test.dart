import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/core/event_input.dart';

void main() {
  group('parseDayAndTime', () {
    test('reads YYYYMMDD with no time', () {
      final p = parseDayAndTime('20261104')!;
      expect(p.day, DateTime(2026, 11, 4));
      expect(p.time, isNull);
    });

    test('reads the full YYYYMMDDTHHmm', () {
      final p = parseDayAndTime('20261104T1315')!;
      expect(p.day, DateTime(2026, 11, 4));
      expect(p.time, const TimeOfDay(hour: 13, minute: 15));
      expect(isFullDayAndTime('20261104T1315'), isTrue);
      expect(isFullDayAndTime('20261104'), isFalse);
    });

    test('also reads the forms with separators', () {
      expect(parseDay('2026-11-04'), DateTime(2026, 11, 4));
      expect(parseDayAndTime('2026-11-04T13:15')!.time,
          const TimeOfDay(hour: 13, minute: 15));
    });

    test('refuses days and times that do not exist', () {
      for (final bad in [
        '',
        '2026110',
        '20260230',
        '20261301',
        '20261104T2460',
        '20261104T2500',
        'tomorrow',
      ]) {
        expect(parseDayAndTime(bad), isNull, reason: bad);
      }
    });
  });

  group('parseTime', () {
    test('reads HHmm and the forms people type', () {
      expect(parseTime('1315'), const TimeOfDay(hour: 13, minute: 15));
      expect(parseTime('13:15'), const TimeOfDay(hour: 13, minute: 15));
      expect(parseTime('9:05'), const TimeOfDay(hour: 9, minute: 5));
      expect(parseTime('930'), const TimeOfDay(hour: 9, minute: 30));
      expect(parseTime('9'), const TimeOfDay(hour: 9, minute: 0));
      expect(parseTime('0000'), const TimeOfDay(hour: 0, minute: 0));
    });

    test('reads the time of a full YYYYMMDDTHHmm', () {
      expect(parseTime('20261104T0745'), const TimeOfDay(hour: 7, minute: 45));
    });

    test('refuses a day, an hour of 24 or more and text', () {
      for (final bad in ['', '2400', '1260', '12:60', '20261104', 'noon']) {
        expect(parseTime(bad), isNull, reason: bad);
      }
    });
  });

  group('parseEventLength', () {
    test('reads minutes and hours', () {
      const cases = {
        '90': Duration(minutes: 90),
        '45m': Duration(minutes: 45),
        '45 min': Duration(minutes: 45),
        '1h': Duration(hours: 1),
        '1h30': Duration(minutes: 90),
        '1h30m': Duration(minutes: 90),
        '1:30': Duration(minutes: 90),
        '1.5h': Duration(minutes: 90),
        '1,5h': Duration(minutes: 90),
        '2H': Duration(hours: 2),
      };
      cases.forEach((text, length) {
        expect(parseEventLength(text), length, reason: text);
      });
    });

    test('refuses zero, nonsense and a length over two weeks', () {
      for (final bad in ['', '0', '0m', 'abc', '1h75', '1:75', '-5', '99999']) {
        expect(parseEventLength(bad), isNull, reason: bad);
      }
    });

    test('formats the way it reads', () {
      for (final d in [
        const Duration(minutes: 45),
        const Duration(hours: 1),
        const Duration(minutes: 90),
        const Duration(hours: 2, minutes: 5),
      ]) {
        expect(parseEventLength(formatEventLength(d)), d);
      }
      expect(formatEventLength(const Duration(minutes: 90)), '1h30');
    });
  });

  test('nextFullHour rounds up to the next hour, also at the end of the day',
      () {
    expect(
        nextFullHour(DateTime(2026, 11, 4, 14, 37)), DateTime(2026, 11, 4, 15));
    expect(nextFullHour(DateTime(2026, 11, 4, 23, 5)), DateTime(2026, 11, 5));
  });
}
