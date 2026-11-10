/// Turns the text of a checklist box into items, and back.
library;

/// The most items a checklist holds (the server refuses more).
const int maxChecklistItems = 50;

/// The longest an item can be (the server refuses more).
const int maxChecklistItemLength = 200;

final _bullet = RegExp(r'^(?:[-*•]|\[[ xX]?\])\s+');

/// The items in [text], one per line.
///
/// Spaces are trimmed and collapsed, a bullet such as `-`, `*` or `[ ]` at the
/// start of a line is dropped (people paste lists), empty lines are skipped and
/// so is an item that was already there (case does not count). This is the
/// same cleaning that the server does, so the box shows what is saved.
List<String> parseChecklistText(String text) {
  final seen = <String, String>{};
  for (final line in text.split(RegExp(r'\r?\n'))) {
    final item = line
        .trim()
        .replaceFirst(_bullet, '')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
    if (item.isNotEmpty) seen.putIfAbsent(item.toLowerCase(), () => item);
  }
  return seen.values.toList();
}

/// The text for the box: one item per line.
String checklistText(List<String> items) => items.join('\n');

/// Why [items] cannot be saved, or null.
String? checklistProblem(List<String> items) {
  if (items.length > maxChecklistItems) {
    return 'At most $maxChecklistItems items. This list has ${items.length}.';
  }
  final long = items.where((i) => i.length > maxChecklistItemLength);
  if (long.isNotEmpty) {
    return 'An item is at most $maxChecklistItemLength characters long.';
  }
  return null;
}
