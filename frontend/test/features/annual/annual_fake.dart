import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tefteri/features/annual/annual_screen.dart';
import 'package:tefteri/theme/theme.dart';

import '../../support/fake_api.dart';

/// The day the annual tests run on: a Sunday in March 2030.
final annualToday = DateTime(2030, 3, 10);

/// A small stateful stand-in for `/annual/...` of one year.
class AnnualServer {
  AnnualServer({
    List<Map<String, Object?>>? goals,
    this.year = 2030,
    this.state = 'current',
    Map<String, Object?>? themes,
  })  : goals = goals ?? [],
        themes = themes ?? themesJson();

  final int year;
  String state;
  final List<Map<String, Object?>> goals;
  final List<Map<String, Object?>> retiredGoals = [];
  Map<String, Object?> themes;
  int _n = 0;

  /// Set to make the next key result write fail.
  ApiFailure? keyResultFailure;

  Map<String, Object?> plan() => annualPlanJson(
      year: year, state: state, goals: goals, retiredGoals: retiredGoals);

  Map<String, Object?> _goal(String id) =>
      goals.firstWhere((g) => g['id'] == id);

  Map<String, Object?> _kr(Map<String, Object?> body, String goalId) {
    final themeIds = [...(body['theme_ids'] as List? ?? const [])];
    return keyResultJson('nkr${++_n}', '${body['metric']}',
        goalId: goalId,
        start: body['start_value'] as num,
        target: body['target'] as num,
        deadline: '${body['deadline']}',
        source: '${body['update_source'] ?? 'manual'}',
        links: [for (final t in themeIds) linkJson('$t', 'Theme $t')],
        flags: themeIds.isEmpty ? [flagJson('no_usable_theme')] : const []);
  }

  Object? Function(RequestOptions) _krRoute(String goalId) =>
      (RequestOptions o) {
        final failure = keyResultFailure;
        if (failure != null) return failure;
        final goal = _goal(goalId);
        final kr = _kr(Map<String, Object?>.from(o.data as Map), goalId);
        goal['key_results'] = [...(goal['key_results'] as List), kr];
        goal['flags'] = <Object?>[];
        return kr;
      };

  /// The routes. The map is kept: a new goal adds its own routes to it.
  Map<String, Object?> routes([Map<String, Object?> extra = const {}]) {
    final r = <String, Object?>{
      'GET /annual/$year': (RequestOptions _) => plan(),
      'GET /annual/themes': (RequestOptions _) => themes,
      'GET /annual/$year/suggestions':
          suggestionsJson(year: year, fromYear: year - 1, hasPlan: false),
      for (final g in goals)
        'POST /annual/goals/${g['id']}/key-results': _krRoute('${g['id']}'),
    };
    r['POST /annual/$year/goals/bulk'] = (RequestOptions o) {
      final body = o.data as Map;
      final made = <Map<String, Object?>>[];
      for (final g in body['goals'] as List) {
        final id = 'ng${++_n}';
        final krs = [
          for (final k in (g as Map)['key_results'] as List? ?? const [])
            _kr(Map<String, Object?>.from(k as Map), id)
        ];
        made.add(annualGoalJson(id, '${g['title']}', keyResults: krs));
        r['POST /annual/goals/$id/key-results'] = _krRoute(id);
      }
      goals.addAll(made);
      return {'batch_id': 'b${++_n}', 'goals': made};
    };
    r.addAll(extra);
    return r;
  }
}

/// Pumps the annual plan of [year] with [routes].
Future<FakeApi> pumpAnnual(WidgetTester tester, Map<String, Object?> routes,
    {int year = 2030,
    Size size = const Size(1000, 2400),
    ThemeMode themeMode = ThemeMode.light,
    Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final api = FakeApi(routes);
  await pumpWithApi(
      tester, api, AnnualScreen(initialYear: year, today: annualToday),
      size: size,
      theme: tefteriLight,
      darkTheme: tefteriDark,
      themeMode: themeMode);
  return api;
}

/// Taps [key] after scrolling it into view, and settles.
Future<void> tapKey(WidgetTester tester, String key) async {
  final f = find.byKey(Key(key));
  await tester.ensureVisible(f.first);
  await tester.pumpAndSettle();
  await tester.tap(f.first);
  await tester.pumpAndSettle();
  // A change reloads lists after the first settle.
  await tester.pump(const Duration(milliseconds: 10));
  await tester.pumpAndSettle();
}

/// Types [text] into the field with [key].
Future<void> typeKey(WidgetTester tester, String key, String text) async {
  await tester.enterText(find.byKey(Key(key)), text);
  await tester.pumpAndSettle();
}

/// Picks [item] in the popup menu with [key].
Future<void> menu(WidgetTester tester, String key, String item) async {
  await tapKey(tester, key);
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
}
