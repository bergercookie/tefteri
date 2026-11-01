@Tags(['screenshots'])
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/notes/note_editor_screen.dart';
import 'package:tefteri/features/notes/notes_screen.dart';

import 'fixtures.dart';
import 'screenshot_helper.dart';

final _process = noteJson('n2', 'Release process',
    kind: 'process',
    body: '1. Run all tests.\n2. Write the release notes.\n'
        '3. Tag the release.\n4. Check the nightly build.',
    taskIds: ['t1']);

void main() {
  testWidgets('notes list', (tester) async {
    final api = FakeApi({
      'GET /notes': (RequestOptions o) => switch (o.queryParameters['kind']) {
            'process' => [
                _process,
                noteJson('n3', 'Weekly planning',
                    kind: 'process',
                    body: '1. Look at last week.',
                    context: 'life'),
              ],
            'custom' => [
                noteJson('n1', 'Home network',
                    body: 'Router and printer setup.', context: 'life'),
                noteJson('n4', 'Server setup',
                    body: 'How the test server works.'),
              ],
            _ => <Object?>[],
          },
    });
    await pumpScreen(tester, api, const NotesScreen());
    await saveScreenshot('notes-list');
  });

  testWidgets('note editor', (tester) async {
    final api = FakeApi({'GET /notes/n2': _process});
    await pumpScreen(tester, api, const NoteEditorScreen(noteId: 'n2'));
    await saveScreenshot('notes-editor');
  });
}
