import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tefteri/features/annual/annual_term_hint.dart';
import 'package:tefteri/features/projects/term_hint.dart';
import 'package:tefteri/features/settings/hints_card.dart';

import '../../support/fake_api.dart';

const _hint = TermHint(
  id: 'monthly-planning-terms',
  title: 'Monthly planning',
  terms: monthlyFocusTerms,
);

Map<String, Object?> _settings(List<String> seen) => {
      'random_time_on_date_drop': false,
      'seen_hints': seen,
    };

FakeApi _api({List<String> seen = const []}) => FakeApi({
      'GET /me/settings': _settings(seen),
      'POST /me/settings/hints/monthly-planning-terms/seen':
          _settings(['monthly-planning-terms']),
      'POST /me/settings/hints/annual-keyResult/seen':
          _settings(['annual-keyResult']),
      'DELETE /me/settings/hints': _settings(const []),
    });

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

/// Waits for the moment when seen hints are sent to the server.
Future<void> _sync(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 2));
  await _settle(tester);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a hint shows the first time, and the server is told it was seen',
      (tester) async {
    final api = _api();
    await pumpWithApi(tester, api, const Scaffold(body: _hint));
    await _settle(tester);
    expect(find.byKey(const Key('term-hint-monthly-planning-terms')),
        findsOneWidget);
    expect(find.text('Monthly planning'), findsOneWidget);
    // Shown once: it is marked as seen without the user doing anything.
    await _sync(tester);
    expect(api.where('POST /me/settings/hints/monthly-planning-terms/seen'),
        hasLength(1));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('term_hint_closed_monthly-planning-terms'), isTrue);
  });

  testWidgets('it stays while its page builds again, even from the start',
      (tester) async {
    final show = ValueNotifier<bool>(true);
    await pumpWithApi(
      tester,
      _api(),
      Scaffold(
        body: ValueListenableBuilder<bool>(
          valueListenable: show,
          builder: (_, on, __) => on ? _hint : const SizedBox(),
        ),
      ),
    );
    await _settle(tester);
    expect(find.byKey(const Key('term-hint-monthly-planning-terms')),
        findsOneWidget);
    // The page removes the hint and builds it again, as a reload does. The
    // reader is still on the same page, so the hint is still there.
    show.value = false;
    await tester.pump();
    expect(find.byKey(const Key('term-hint-monthly-planning-terms')),
        findsNothing);
    show.value = true;
    await _settle(tester);
    expect(find.byKey(const Key('term-hint-monthly-planning-terms')),
        findsOneWidget);
  });

  testWidgets('the next start does not show it again', (tester) async {
    // This device saw the hint before: the stored choice hides it.
    SharedPreferences.setMockInitialValues(
        {'term_hint_closed_monthly-planning-terms': true});
    final api = _api();
    await pumpWithApi(tester, api, const Scaffold(body: _hint));
    await _settle(tester);
    expect(find.byKey(const Key('term-hint-monthly-planning-terms')),
        findsNothing);
    // A hint that is hidden is not marked again.
    expect(api.where('POST /me/settings/hints/monthly-planning-terms/seen'),
        isEmpty);
  });

  testWidgets('a hint seen on another device is hidden here too',
      (tester) async {
    // Nothing is stored on this device; the server knows the user saw it.
    await pumpWithApi(tester, _api(seen: ['monthly-planning-terms']),
        const Scaffold(body: _hint));
    await _settle(tester);
    expect(find.byKey(const Key('term-hint-monthly-planning-terms')),
        findsNothing);
  });

  testWidgets('the close button hides it now and tells the server',
      (tester) async {
    final api = _api();
    await pumpWithApi(tester, api, const Scaffold(body: _hint));
    await _settle(tester);
    await tester
        .tap(find.byKey(const Key('term-hint-close-monthly-planning-terms')));
    await _settle(tester);
    expect(find.byKey(const Key('term-hint-monthly-planning-terms')),
        findsNothing);
    expect(api.where('POST /me/settings/hints/monthly-planning-terms/seen'),
        isNotEmpty);
  });

  testWidgets('without the server, this device\'s choice is used',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {'term_hint_closed_monthly-planning-terms': true});
    // No route for the settings: the server does not answer.
    await pumpWithApi(tester, FakeApi({}), const Scaffold(body: _hint));
    await _settle(tester);
    expect(find.byKey(const Key('term-hint-monthly-planning-terms')),
        findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a hint of annual planning shows once in the same way',
      (tester) async {
    final api = _api();
    await pumpWithApi(tester, api,
        const Scaffold(body: AnnualTermHint(AnnualTerm.keyResult)));
    await _settle(tester);
    expect(find.byKey(const Key('annual-hint-keyResult')), findsOneWidget);
    await _sync(tester);
    expect(api.where('POST /me/settings/hints/annual-keyResult/seen'),
        hasLength(1));
  });

  group('the setting that shows the hints again', () {
    testWidgets('clears what this device and the server remember',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'term_hint_closed_monthly-planning-terms': true,
        'term_hint_closed_annual-keyResult': true,
        'unrelated': 'kept',
      });
      final api = _api(seen: ['monthly-planning-terms']);
      await pumpWithApi(tester, api,
          const Scaffold(body: Column(children: [HintsCard(), _hint])));
      await _settle(tester);
      expect(find.byKey(const Key('term-hint-monthly-planning-terms')),
          findsNothing);
      await tester.tap(find.byKey(const Key('reset-hints')));
      await _settle(tester);
      expect(api.where('DELETE /me/settings/hints'), hasLength(1));
      expect(find.byKey(const Key('hints-reset-note')), findsOneWidget);
      // The hint shows again at once, and the stored choices are gone.
      expect(find.byKey(const Key('term-hint-monthly-planning-terms')),
          findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(
          prefs.getKeys().where((k) => k.startsWith('term_hint_closed_')),
          // The hint that shows again is marked as seen once more.
          ['term_hint_closed_monthly-planning-terms']);
      expect(prefs.getString('unrelated'), 'kept');
    });
  });
}
