import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/checklists/checklist_text.dart';

void main() {
  group('parseChecklistText', () {
    test('one item per line, trimmed, empty lines skipped', () {
      expect(parseChecklistText('  Clear the inbox \n\n   \nCheck goals\n'),
          ['Clear the inbox', 'Check goals']);
    });

    test('spaces inside an item collapse, as on the server', () {
      expect(parseChecklistText('Review   the\tcalendar'),
          ['Review the calendar']);
    });

    test('a repeat is dropped, whatever its case', () {
      expect(parseChecklistText('Clear the inbox\nclear THE inbox\nOther'),
          ['Clear the inbox', 'Other']);
    });

    test('bullets from a pasted list are removed', () {
      expect(
          parseChecklistText('- one\n* two\n• three\n[ ] four\n[x] five\n-six'),
          ['one', 'two', 'three', 'four', 'five', '-six']);
    });

    test('windows line ends work', () {
      expect(parseChecklistText('a\r\nb\r\n'), ['a', 'b']);
    });

    test('empty text has no items', () {
      expect(parseChecklistText(''), isEmpty);
      expect(parseChecklistText('  \n \n'), isEmpty);
    });
  });

  test('checklistText puts one item on each line', () {
    expect(checklistText(['a', 'b']), 'a\nb');
    expect(checklistText([]), '');
  });

  group('checklistProblem', () {
    test('accepts the limits', () {
      expect(
          checklistProblem(
              [for (var i = 0; i < maxChecklistItems; i++) 'Item $i']),
          isNull);
      expect(checklistProblem(['x' * maxChecklistItemLength]), isNull);
    });

    test('refuses too many items and too long ones', () {
      expect(
          checklistProblem(
              [for (var i = 0; i <= maxChecklistItems; i++) 'Item $i']),
          contains('At most 50 items'));
      expect(checklistProblem(['x' * (maxChecklistItemLength + 1)]),
          contains('200 characters'));
    });
  });
}
