/// Shared setup for the documentation screenshots.
///
/// Each screenshot test pumps one screen with fake data (never real
/// credentials or personal data) and writes a PNG to `docs/images/`.
/// Run them by hand with `just docs::screenshots`; they are not part of
/// `just test`.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/core/api_client.dart';

import '../support/fake_api.dart';

export '../support/fake_api.dart';

/// Window size of every screenshot, in logical pixels.
const screenshotSize = Size(1100, 720);

bool _fontsLoaded = false;

/// Loads every font of the app bundle (Roboto and the Material icons), so
/// the images show real glyphs instead of boxes.
Future<void> loadFonts() async {
  if (_fontsLoaded) return;
  final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json'))
      as List<dynamic>;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader('${entry['family']}');
    for (final font in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load('${font['asset']}'));
    }
    await loader.load();
  }
  _fontsLoaded = true;
}

/// The app theme, with the bundled font.
ThemeData screenshotTheme() => ThemeData(
    colorSchemeSeed: Colors.indigo, useMaterial3: true, fontFamily: 'Roboto');

/// Pumps [screen] with the fake backend [api] in a fixed-size window.
///
/// [overrides] replace more providers, for example the sign-in state.
Future<void> pumpScreen(WidgetTester tester, FakeApi api, Widget screen,
    {List<Override> overrides = const [], Size size = screenshotSize}) async {
  await loadFonts();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = api;
  await tester.pumpWidget(ProviderScope(
    overrides: [dioProvider.overrideWithValue(dio), ...overrides],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: screenshotTheme(),
      home: screen,
    ),
  ));
  await tester.pumpAndSettle();
}

/// Writes the current window to `docs/images/<name>.png`.
Future<void> saveScreenshot(String name) => expectLater(
    find.byType(MaterialApp).first,
    matchesGoldenFile('../../../docs/images/$name.png'));
