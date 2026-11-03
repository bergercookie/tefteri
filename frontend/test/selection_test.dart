import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/app.dart';
import 'package:tefteri/core/api_client.dart';
import 'package:tefteri/core/auth_controller.dart';

import 'features/planner/planner_helpers.dart';
import 'support/fake_api.dart';

class _SignedIn extends AuthController {
  _SignedIn(super.ref) {
    state = const AuthState(signedIn: true);
  }
}

Future<void> _pumpApp(WidgetTester tester, FakeApi api) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = api;
  await tester.pumpWidget(ProviderScope(
    overrides: [
      dioProvider.overrideWithValue(dio),
      authControllerProvider.overrideWith(_SignedIn.new),
    ],
    child: const TefteriApp(),
  ));
  await tester.pumpAndSettle();
}

/// The text that "select all" and "copy" put on the clipboard.
Future<String> _selectAll(WidgetTester tester) async {
  var copied = '';
  tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') {
      copied = (call.arguments as Map)['text'] as String;
    }
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
  final state =
      tester.state<SelectableRegionState>(find.byType(SelectableRegion));
  state.selectAll();
  await tester.pump();
  // ignore: deprecated_member_use
  state.copySelection(SelectionChangedCause.keyboard);
  await tester.pump();
  return copied;
}

void main() {
  testWidgets('the whole app is one selection area', (tester) async {
    await _pumpApp(tester, plannerApi());
    expect(find.byType(SelectionArea), findsOneWidget);
    // text of a screen is inside it, for example the title of the app bar
    expect(
        find.ancestor(
            of: find.text('Planner').last,
            matching: find.byType(SelectionArea)),
        findsOneWidget);
  });

  testWidgets('text on a screen can be selected', (tester) async {
    await _pumpApp(tester, plannerApi());
    final text = await _selectAll(tester);
    expect(text, contains('Planner'));
    expect(text, contains('all day'));
  });

  testWidgets('an error message can be selected and copied', (tester) async {
    final api = plannerApi(extra: {
      'PUT /tasks/t1/schedule': const ApiFailure(
          409,
          'The item changed in Vikunja. Sync to see the new version. '
              'Open the Conflicts screen to choose a version.',
          'remote_conflict'),
    });
    await _pumpApp(tester, api);
    await dragTo(tester, find.byKey(const Key('task-t1')),
        slotPoint(tester, wednesday, 9, 0));
    expect(find.textContaining('The item changed in Vikunja'), findsOneWidget);
    final text = await _selectAll(tester);
    expect(text, contains('Open the Conflicts screen to choose a version.'));
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('a task row is a drag handle, so its text is not selectable',
      (tester) async {
    await _pumpApp(tester, plannerApi());
    final text = await _selectAll(tester);
    expect(find.text('Write report'), findsOneWidget);
    expect(text, isNot(contains('Write report')));
  });
}
