import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tefteri/core/html_description.dart';
import 'package:tefteri/core/open_url.dart';

/// The first span in [root] that has a tap recognizer.
TextSpan? _linkSpan(InlineSpan root) {
  if (root is! TextSpan) return null;
  if (root.recognizer != null) return root;
  for (final child in root.children ?? const <InlineSpan>[]) {
    final found = _linkSpan(child);
    if (found != null) return found;
  }
  return null;
}

void main() {
  test('looksLikeHtml tells markup from plain text', () {
    expect(looksLikeHtml('<p>Hi</p>'), isTrue);
    expect(looksLikeHtml('Cover the Q3 numbers.\nAdd the chart.'), isFalse);
    expect(looksLikeHtml('a < b and c > d'), isFalse);
  });

  testWidgets('shows formatted text without tags and opens links',
      (tester) async {
    final opened = <Uri>[];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        openUrlProvider.overrideWithValue((uri) async {
          opened.add(uri);
          return true;
        }),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: HtmlDescription(
            html: '<p><a href="https://example.com/share/1">'
                'https://example.com/share/1</a></p>'
                '<p>Plan <strong>first</strong>, then <em>ship</em>.<br>'
                'Done &amp; dusted.</p>'
                '<ul><li>one</li><li>two</li></ul>'
                '<p><a href="javascript:alert(1)">unsafe</a></p>',
          ),
        ),
      ),
    ));

    expect(find.textContaining('<p>'), findsNothing);
    expect(find.text('•'), findsNWidgets(2));

    final texts = tester.widgetList<Text>(find.byType(Text)).toList();
    final plain =
        texts.map((t) => t.textSpan?.toPlainText() ?? t.data ?? '').join('|');
    expect(plain, contains('Plan first, then ship.'));
    expect(plain, contains('Done & dusted.'));
    expect(plain, contains('one'));
    expect(plain, contains('unsafe'));

    // Only the http link is clickable; the javascript: one is plain text.
    final links = [
      for (final t in texts)
        if (t.textSpan != null) _linkSpan(t.textSpan!),
    ];
    expect(links.where((s) => s != null), hasLength(1));
    final link = links.firstWhere((s) => s != null)!;
    (link.recognizer! as TapGestureRecognizer).onTap!();
    expect(opened, [Uri.parse('https://example.com/share/1')]);
  });
}
