import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/core/update_check.dart';
import 'package:tefteri/core/versions.dart';

void main() {
  group('releases', () {
    test('reads a release tag', () {
      final r = parseStableRelease({'tag_name': 'v1.5.0', 'html_url': 'u'})!;
      expect((r.name, r.url, r.label), ('1.5.0', 'u', '1.5.0'));
      // The old rolling pre-release is not a version.
      expect(parseStableRelease({'tag_name': 'nightly'}), isNull);
    });
  });

  group('compareWithLatest', () {
    const latest = PublishedRelease(name: '1.5.3', url: '', label: '1.5.3');

    UpdateStatus check(AppVersion v) => compareWithLatest(v, latest).status;

    test('a higher version, also by one patch, is an update', () {
      expect(check(const AppVersion('1.5.2', 50)), UpdateStatus.available);
      expect(check(const AppVersion('1.4.9', 50)), UpdateStatus.available);
      expect(check(const AppVersion('0.9.99', 1)), UpdateStatus.available);
    });

    test('the same or a higher installed version is up to date', () {
      expect(check(const AppVersion('1.5.3', 7)), UpdateStatus.upToDate);
      expect(check(const AppVersion('1.5.4', 1)), UpdateStatus.upToDate);
      expect(check(const AppVersion('2.0.0', 1)), UpdateStatus.upToDate);
    });

    test('an unreadable version is not reported as an update', () {
      expect(check(const AppVersion('dev', 0)), UpdateStatus.upToDate);
    });
  });
}
