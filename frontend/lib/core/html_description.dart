/// Renders the HTML that the task apps keep in a task description (Vikunja
/// stores rich text as HTML) as formatted text instead of raw markup.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../theme/theme.dart';
import 'open_url.dart';

/// Whether [text] contains HTML tags, so it should be rendered rather than
/// shown as it is.
bool looksLikeHtml(String text) => RegExp(r'<[a-zA-Z/][^>]*>').hasMatch(text);

const _blockTags = {
  'p',
  'div',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'blockquote',
  'pre',
  'ul',
  'ol',
};

const _safeLinkSchemes = {'http', 'https', 'mailto'};

/// Formatted, read-only view of a description. Links open in the browser.
class HtmlDescription extends ConsumerStatefulWidget {
  /// Creates the view of [html].
  const HtmlDescription({super.key, required this.html});

  /// The HTML to render.
  final String html;

  @override
  ConsumerState<HtmlDescription> createState() => _HtmlDescriptionState();
}

class _HtmlDescriptionState extends ConsumerState<HtmlDescription> {
  final List<TapGestureRecognizer> _links = [];

  @override
  void dispose() {
    _disposeLinks();
    super.dispose();
  }

  void _disposeLinks() {
    for (final link in _links) {
      link.dispose();
    }
    _links.clear();
  }

  @override
  Widget build(BuildContext context) {
    _disposeLinks();
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium!;
    final linkColor = theme.colorScheme.primary;
    final fragment = html_parser.parseFragment(widget.html);

    final blocks = <Widget>[];
    final run = <dom.Node>[];

    void flushRun() {
      final text = run.map((n) => n.text ?? '').join();
      if (text.trim().isNotEmpty) {
        blocks.add(_richText([
          for (final node in run) ..._spans(node, style, linkColor),
        ]));
      }
      run.clear();
    }

    for (final node in fragment.nodes) {
      if (node is dom.Element && _blockTags.contains(node.localName)) {
        flushRun();
        final block = _block(node, style, linkColor, theme);
        if (block != null) blocks.add(block);
      } else {
        run.add(node);
      }
    }
    flushRun();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) const SizedBox(height: Space.sm),
          blocks[i],
        ],
      ],
    );
  }

  Widget _richText(List<InlineSpan> spans) =>
      Text.rich(TextSpan(children: spans));

  Widget? _block(
      dom.Element element, TextStyle style, Color linkColor, ThemeData theme) {
    final tag = element.localName ?? '';
    if (tag == 'ul' || tag == 'ol') {
      final items = element.children.where((c) => c.localName == 'li').toList();
      if (items.isEmpty) return null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(left: Space.sm, top: Space.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 24,
                    child: Text(tag == 'ol' ? '${i + 1}.' : '•', style: style),
                  ),
                  Expanded(
                    child: _richText([
                      for (final node in items[i].nodes)
                        ..._spans(node, style, linkColor),
                    ]),
                  ),
                ],
              ),
            ),
        ],
      );
    }
    if ((element.text).trim().isEmpty) return null;
    final blockStyle = tag.startsWith('h')
        ? theme.textTheme.titleSmall!.copyWith(fontWeight: FontWeight.w600)
        : style;
    return _richText([
      for (final node in element.nodes) ..._spans(node, blockStyle, linkColor),
    ]);
  }

  List<InlineSpan> _spans(
    dom.Node node,
    TextStyle style,
    Color linkColor, {
    TapGestureRecognizer? link,
  }) {
    if (node is dom.Text) {
      final text = node.text.replaceAll(RegExp(r'\s+'), ' ');
      if (text.isEmpty) return const [];
      return [TextSpan(text: text, style: style, recognizer: link)];
    }
    if (node is! dom.Element) return const [];

    final tag = node.localName ?? '';
    if (tag == 'br') return [TextSpan(text: '\n', style: style)];

    var childStyle = style;
    var childLink = link;
    switch (tag) {
      case 'strong':
      case 'b':
        childStyle = style.copyWith(fontWeight: FontWeight.w600);
        break;
      case 'em':
      case 'i':
        childStyle = style.copyWith(fontStyle: FontStyle.italic);
        break;
      case 'a':
        final uri = Uri.tryParse(node.attributes['href'] ?? '');
        if (uri != null && _safeLinkSchemes.contains(uri.scheme)) {
          final recognizer = TapGestureRecognizer()
            ..onTap = () => ref.read(openUrlProvider)(uri);
          _links.add(recognizer);
          childLink = recognizer;
          childStyle = style.copyWith(
            color: linkColor,
            decoration: TextDecoration.underline,
            decorationColor: linkColor,
          );
        }
        break;
    }

    return [
      for (final child in node.nodes)
        ..._spans(child, childStyle, linkColor, link: childLink),
    ];
  }
}
