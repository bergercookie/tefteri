import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/app.dart';
import 'package:tefteri/core/api_client.dart';
import 'package:tefteri/core/auth_controller.dart';
import 'package:tefteri/core/shortcuts/keymap.dart';
import 'package:tefteri/features/daily/daily_screen.dart';
import 'package:tefteri/features/month/month_screen.dart';
import 'package:tefteri/features/planner/planner_screen.dart';
import 'package:tefteri/features/week/week_screen.dart';

import '../support/fake_api.dart';

/// The Android home screen widget has four buttons. Each opens a link such as
/// `tefteri://app/week`; Flutter gives the path to the router. These tests
/// cover the Dart side and keep the Android files in step with the app. The
/// widget itself runs only on a device.
const _android = 'android/app/src/main';

class _SignedIn extends AuthController {
  _SignedIn(super.ref) {
    state = const AuthState(signedIn: true);
  }
}

FakeApi _api() => FakeApi({
      'GET /calendar': <Object?>[],
      'GET /tasks': <Object?>[],
      'GET /tasks/counts': <String, int>{},
      'GET /connections': <Object?>[],
      'GET /sync/status': {'last_sync_at': null, 'results': <Object?>[]},
      'GET /views/day/2026-11-04': {
        'date': '2026-11-04',
        'entries': <Object?>[],
        'tasks': <Object?>[],
        'note': null,
      },
    });

Future<void> _start(WidgetTester tester, {String? route}) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // The route that Android gives Flutter when the app starts from a link.
  if (route != null) {
    tester.platformDispatcher.defaultRouteNameTestValue = route;
    addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
  }
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))
    ..httpClientAdapter = _api();
  final container = ProviderContainer(overrides: [
    dioProvider.overrideWithValue(dio),
    authControllerProvider.overrideWith(_SignedIn.new),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(routerConfig: container.read(routerProvider)),
  ));
  await tester.pumpAndSettle();
}

/// What the running app receives when a link arrives while it is open.
Future<void> _link(WidgetTester tester, String path) async {
  final message = const JSONMethodCodec()
      .encodeMethodCall(MethodCall('pushRouteInformation', {'location': path}));
  await tester.binding.defaultBinaryMessenger
      .handlePlatformMessage('flutter/navigation', message, (_) {});
  await tester.pumpAndSettle();
}

void main() {
  const screens = <String, Type>{
    '/daily': DailyScreen,
    '/week': WeekScreen,
    '/month': MonthScreen,
    '/': PlannerScreen,
  };

  for (final e in screens.entries) {
    testWidgets('a start from the link ${e.key} opens that view',
        (tester) async {
      await _start(tester, route: e.key);
      expect(find.byType(e.value), findsOneWidget);
    });
  }

  testWidgets('a link opens its view while the app is open', (tester) async {
    await _start(tester);
    expect(find.byType(PlannerScreen), findsOneWidget);
    for (final e in screens.entries.take(3)) {
      await _link(tester, e.key);
      expect(find.byType(e.value), findsOneWidget, reason: e.key);
    }
    // And back to the planner, the fourth button.
    await _link(tester, '/');
    expect(find.byType(PlannerScreen), findsOneWidget);
  });

  group('the Android files', () {
    final kotlin =
        File('$_android/kotlin/dev/bergercookie/tefteri/NavWidgetProvider.kt')
            .readAsStringSync();

    test('the widget has four buttons, each with a path of an app view', () {
      final paths = RegExp(r'Button\(R\.id\.widget_(\w+), "([^"]*)"\)')
          .allMatches(kotlin)
          .map((m) => (m.group(1)!, m.group(2)!))
          .toList();
      expect(paths, [
        ('today', '/daily'),
        ('week', '/week'),
        ('month', '/month'),
        ('planner', '/'),
      ]);
      final known = appViews.map((v) => v.path).toSet();
      for (final (_, path) in paths) {
        expect(known, contains(path));
      }
      // The screens in this test are those of the four paths.
      expect(screens.keys.toSet(), paths.map((p) => p.$2).toSet());
    });

    test('every button has a view in the layout, an icon and a label', () {
      final layout =
          File('$_android/res/layout/tefteri_widget.xml').readAsStringSync();
      for (final name in ['today', 'week', 'month', 'planner']) {
        expect(layout, contains('@+id/widget_$name'));
        expect(layout, contains('@drawable/ic_widget_$name'));
        expect(layout, contains('@string/widget_$name"'));
        expect(layout, contains('@string/widget_${name}_description'));
        expect(File('$_android/res/drawable/ic_widget_$name.xml').existsSync(),
            isTrue);
      }
    });

    test('the widget is four cells wide and one cell high', () {
      final info =
          File('$_android/res/xml/tefteri_widget_info.xml').readAsStringSync();
      expect(info, contains('android:targetCellWidth="4"'));
      expect(info, contains('android:targetCellHeight="1"'));
      expect(info, contains('android:widgetCategory="home_screen"'));
      // Four cells are 250 dp wide (70 dp a cell, less 30 dp), one cell 40 dp.
      expect(info, contains('android:minWidth="250dp"'));
      expect(info, contains('android:minHeight="40dp"'));
    });

    test('the manifest declares the widget and the link', () {
      final manifest = File('$_android/AndroidManifest.xml').readAsStringSync();
      expect(manifest, contains('android:name=".NavWidgetProvider"'));
      expect(manifest, contains('android.appwidget.action.APPWIDGET_UPDATE'));
      expect(manifest, contains('@xml/tefteri_widget_info'));
      expect(manifest,
          contains('<data android:scheme="tefteri" android:host="app"/>'));
      expect(manifest, contains('flutter_deeplinking_enabled'));
    });

    test('the colors have a dark version', () {
      final light =
          File('$_android/res/values/widget_colors.xml').readAsStringSync();
      final dark = File('$_android/res/values-night/widget_colors.xml')
          .readAsStringSync();
      for (final name in ['paper', 'rule', 'ink', 'accent', 'pressed']) {
        expect(light, contains('name="widget_$name"'));
        expect(dark, contains('name="widget_$name"'));
      }
    });
  });

  group('the agenda widget files', () {
    String read(String path) => File('$_android/$path').readAsStringSync();
    const kotlin = 'kotlin/dev/bergercookie/tefteri';

    test('it is declared with its list service in the manifest', () {
      final manifest = read('AndroidManifest.xml');
      expect(manifest, contains('android:name=".AgendaWidgetProvider"'));
      expect(manifest, contains('@xml/tefteri_agenda_widget_info'));
      expect(manifest, contains('android:name=".AgendaWidgetService"'));
      expect(manifest, contains('android.permission.BIND_REMOTEVIEWS'));
      for (final name in [
        'AgendaWidgetProvider',
        'AgendaWidgetService',
        'AgendaData',
      ]) {
        expect(File('$_android/$kotlin/$name.kt').existsSync(), isTrue);
      }
    });

    test('it has arrows, a date, a list and rows in the layouts', () {
      final layout = read('res/layout/tefteri_agenda_widget.xml');
      for (final id in [
        'agenda_previous',
        'agenda_next',
        'agenda_date',
        'agenda_refresh',
        'agenda_list',
      ]) {
        expect(layout, contains('@+id/$id'));
      }
      final row = read('res/layout/tefteri_agenda_row.xml');
      for (final id in [
        'agenda_row',
        'agenda_swatch',
        'agenda_title',
        'agenda_time',
      ]) {
        expect(row, contains('@+id/$id'));
      }
      for (final icon in ['arrow_left', 'arrow_right', 'refresh']) {
        expect(File('$_android/res/drawable/ic_widget_$icon.xml').existsSync(),
            isTrue);
      }
    });

    test('it reads the day from the server with the saved login', () {
      final data = read('$kotlin/AgendaData.kt');
      expect(data, contains('flutter.session_token'));
      expect(data, contains('flutter.server_address'));
      expect(data, contains('/api/v1/views/day/'));
      expect(data, contains('Bearer'));
      expect(data, contains('X-Tefteri-Client'));
    });

    test('it stays on today unless an arrow was used', () {
      final provider = read('$kotlin/AgendaWidgetProvider.kt');
      expect(provider, contains('ACTION_PREVIOUS'));
      expect(provider, contains('ACTION_NEXT'));
      // The chosen day counts only on the day that it was chosen.
      expect(provider, contains('set_on_'));
      expect(provider, contains('shown_'));
      // And the choice is written at once, so that no redraw can read an older day.
      expect(provider, contains('.commit()'));
    });

    test('its strings and colors exist, and the colors have a dark version',
        () {
      final strings = read('res/values/widget_strings.xml');
      for (final name in ['label', 'description', 'empty', 'sign_in']) {
        expect(strings, contains('name="agenda_$name"'));
      }
      expect(read('res/values/widget_colors.xml'),
          contains('name="widget_muted"'));
      expect(read('res/values-night/widget_colors.xml'),
          contains('name="widget_muted"'));
    });

    test('it is four cells wide and three cells high', () {
      final info = read('res/xml/tefteri_agenda_widget_info.xml');
      expect(info, contains('android:targetCellWidth="4"'));
      expect(info, contains('android:targetCellHeight="3"'));
      // The picker shows this layout; without it the card is blank.
      expect(info,
          contains('android:previewLayout="@layout/tefteri_agenda_preview"'));
      expect(info, contains('android:widgetCategory="home_screen"'));
    });
  });
}
