import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/core/update_check.dart';
import 'package:tefteri/core/versions.dart';

void main() {
  group('releases', () {
    test('reads a standard release tag', () {
      final r = parseStableRelease({'tag_name': 'v1.5.0', 'html_url': 'u'})!;
      expect((r.name, r.post, r.url), ('1.5.0', null, 'u'));
      expect(parseStableRelease({'tag_name': 'nightly'}), isNull);
    });

    test('reads the nightly title', () {
      final r = parseNightlyRelease(
          {'name': 'Nightly 1.4.0.a1b2c3d.post3', 'html_url': 'u'})!;
      expect((r.name, r.post), ('1.4.0', 3));
      expect(parseNightlyRelease({'name': 'Something else'}), isNull);
    });
  });

  group('compareWithLatest', () {
    const std =
        PublishedRelease(name: '1.5.0', post: null, url: '', label: '1.5.0');
    const nightly = PublishedRelease(
        name: '1.4.0', post: 3, url: '', label: '1.4.0 nightly 3');

    UpdateStatus standard(AppVersion v) =>
        compareWithLatest(v, std, UpdateChannel.standard).status;
    UpdateStatus nightlyCheck(AppVersion v) =>
        compareWithLatest(v, nightly, UpdateChannel.nightly).status;

    test('standard: only a higher version is an update', () {
      expect(standard(const AppVersion('1.4.9', 50)), UpdateStatus.available);
      expect(standard(const AppVersion('1.5.0', 7)), UpdateStatus.upToDate);
      expect(standard(const AppVersion('2.0.0', 1)), UpdateStatus.upToDate);
    });

    test('nightly: the post number decides within a version', () {
      expect(
          nightlyCheck(const AppVersion('1.4.0', 2)), UpdateStatus.available);
      expect(nightlyCheck(const AppVersion('1.4.0', 3)), UpdateStatus.upToDate);
      expect(
          nightlyCheck(const AppVersion('1.3.0', 99)), UpdateStatus.available);
      expect(nightlyCheck(const AppVersion('1.4.1', 1)), UpdateStatus.upToDate);
    });

    test('the channel changes the answer for the same install', () {
      const installed = AppVersion('1.4.0', 2);
      // A nightly of 1.4.0 is newer; the standard release 1.5.0 is too, but a
      // standard 1.4.0 would not be.
      expect(nightlyCheck(installed), UpdateStatus.available);
      const old =
          PublishedRelease(name: '1.4.0', post: null, url: '', label: '1.4.0');
      expect(compareWithLatest(installed, old, UpdateChannel.standard).status,
          UpdateStatus.upToDate);
    });

    test('an unreadable version is not reported as an update', () {
      expect(standard(const AppVersion('dev', 0)), UpdateStatus.upToDate);
    });
  });
}
