@Tags(['screenshots'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/features/conflicts/conflicts_screen.dart';

import 'screenshot_helper.dart';

void main() {
  testWidgets('conflict with both versions', (tester) async {
    final api = FakeApi({
      'GET /conflicts': [
        {
          'id': 'k1',
          'entity_type': 'task',
          'entity_id': 't1',
          'local_snapshot': {
            'title': 'Write the release notes',
            'status': 'open',
            'due_at': '2026-11-03T17:00:00+00:00',
          },
          'remote_snapshot': {
            'title': 'Write the release notes for v1',
            'status': 'open',
            'due_at': '2026-11-04T17:00:00+00:00',
          },
          'created_at': '2026-11-02T08:15:00Z',
        },
      ],
    });
    await pumpScreen(tester, api, const ConflictsScreen());
    await saveScreenshot('conflicts');
  });
}
