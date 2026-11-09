/// Find on page: Ctrl+F opens a bar that searches the text on the screen and
/// marks every match.
///
/// The browser's own find cannot do this for the web client. The app draws its
/// text on a canvas, and the invisible copy of it that the browser can search
/// sits at the corner of each element, not under the words, so the browser
/// finds a word but marks nothing where the user sees it. The bar reads the
/// text from the render tree and draws the marks itself. It also works in the
/// Android and Linux apps, which have no find of their own.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/theme.dart';

/// The most matches that the bar marks. A page with more is not a page to read
/// match by match.
const int maxFindMatches = 500;

/// One place where the text was found.
@immutable
class FindMatch {
  /// Creates a match of [start] to [end] in [paragraph].
  const FindMatch(this.paragraph, this.start, this.end);

  /// The text that holds the match.
  final RenderParagraph paragraph;

  /// Offset of the first character.
  final int start;

  /// Offset after the last character.
  final int end;

  /// The boxes of the match on the screen. Empty when the text is out of
  /// sight (scrolled away, or clipped).
  List<Rect> screenRects() {
    if (!paragraph.attached || !paragraph.hasSize) return const [];
    final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: end));
    if (boxes.isEmpty) return const [];
    final toScreen = paragraph.getTransformTo(null);
    final clip = _visibleArea(paragraph);
    final rects = <Rect>[];
    for (final b in boxes) {
      var r = MatrixUtils.transformRect(toScreen, b.toRect());
      if (clip != null) {
        r = r.intersect(clip);
        if (r.isEmpty) continue;
      }
      rects.add(r);
    }
    return rects;
  }
}

/// The part of the screen in which [object] can be seen: the clips of its
/// ancestors (scroll views, clipped boxes) cut together.
Rect? _visibleArea(RenderObject object) {
  Rect? area;
  RenderObject child = object;
  var parent = object.parent;
  while (parent is RenderObject) {
    final clip = parent.describeApproximatePaintClip(child);
    if (clip != null) {
      final onScreen =
          MatrixUtils.transformRect(parent.getTransformTo(null), clip);
      area = area == null ? onScreen : area.intersect(onScreen);
    }
    child = parent;
    parent = parent.parent;
  }
  return area;
}

/// Collects the texts under [root] that are on a screen: it skips what is
/// off stage and the pages that an indexed stack does not show.
void collectParagraphs(RenderObject root, List<RenderParagraph> into) {
  if (root is RenderParagraph) {
    into.add(root);
    return;
  }
  if (root is RenderOffstage && root.offstage) return;
  if (root is RenderIndexedStack) {
    final shown = root.index;
    if (shown == null) return;
    var i = 0;
    root.visitChildren((c) {
      if (i++ == shown) collectParagraphs(c, into);
    });
    return;
  }
  root.visitChildren((c) => collectParagraphs(c, into));
}

/// Finds every place of [query] (without regard to upper and lower case) in
/// the texts under [root], from the top of the screen to the bottom.
List<FindMatch> findInTree(RenderObject root, String query) {
  if (query.isEmpty) return const [];
  final paragraphs = <RenderParagraph>[];
  collectParagraphs(root, paragraphs);
  final needle = query.toLowerCase();
  final found = <(double, double, FindMatch)>[];
  for (final p in paragraphs) {
    if (!p.attached || !p.hasSize) continue;
    final text = p.text.toPlainText(includePlaceholders: false).toLowerCase();
    var from = 0;
    while (found.length < maxFindMatches) {
      final at = text.indexOf(needle, from);
      if (at < 0) break;
      final match = FindMatch(p, at, at + needle.length);
      final origin = p.localToGlobal(Offset.zero);
      found.add((origin.dy, origin.dx, match));
      from = at + math.max(1, needle.length);
    }
  }
  // Reading order: top to bottom, then left to right, then along the text.
  found.sort((a, b) {
    final byTop = a.$1.compareTo(b.$1);
    if (byTop != 0) return byTop;
    final byLeft = a.$2.compareTo(b.$2);
    return byLeft != 0 ? byLeft : a.$3.start.compareTo(b.$3.start);
  });
  return [for (final f in found) f.$3];
}

/// What the find bar shows.
@immutable
class FindState {
  /// Creates a state.
  const FindState({
    this.open = false,
    this.query = '',
    this.matches = const [],
    this.current = 0,
  });

  /// The bar is on the screen.
  final bool open;

  /// The text to find.
  final String query;

  /// Where it is on the screen now.
  final List<FindMatch> matches;

  /// Index of the match that the user is at.
  final int current;
}

/// Runs the find bar: the query, the matches and the match that the user is
/// at. [rootOf] gives the render tree to search.
class FindController extends StateNotifier<FindState> {
  /// Creates the controller.
  FindController() : super(const FindState());

  /// Gives the root of the tree to search. The bar sets it.
  RenderObject? Function() rootOf = () => null;

  /// Counts up each time the user asks to focus the field.
  final focusRequests = ValueNotifier<int>(0);

  /// Shows the bar, or moves the focus to its field when it is open.
  void open() {
    if (!state.open) state = FindState(open: true, query: state.query);
    focusRequests.value++;
    refresh(reveal: false);
  }

  /// Hides the bar and its marks.
  void close() => state = FindState(query: state.query);

  /// Searches [query].
  void setQuery(String query) {
    state = FindState(open: state.open, query: query);
    refresh(reveal: true);
  }

  /// Searches again, because the screen changed. Keeps the match that the
  /// user is at when it is still there.
  void refresh({bool reveal = false}) {
    if (!state.open) return;
    final root = rootOf();
    if (root == null) return;
    final matches = findInTree(root, state.query);
    var current = state.current;
    if (matches.isEmpty) {
      current = 0;
    } else if (state.matches.isNotEmpty &&
        state.current < state.matches.length) {
      final old = state.matches[state.current];
      final same = matches.indexWhere(
          (m) => identical(m.paragraph, old.paragraph) && m.start == old.start);
      current = same >= 0 ? same : math.min(state.current, matches.length - 1);
    }
    if (_same(matches, state.matches) && current == state.current) return;
    state = FindState(
        open: true, query: state.query, matches: matches, current: current);
    if (reveal) _reveal();
  }

  static bool _same(List<FindMatch> a, List<FindMatch> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i].paragraph, b[i].paragraph) ||
          a[i].start != b[i].start) {
        return false;
      }
    }
    return true;
  }

  /// Goes to the next match (the first one after the last).
  void next() => _go(1);

  /// Goes to the match before (the last one before the first).
  void previous() => _go(-1);

  void _go(int step) {
    final n = state.matches.length;
    if (n == 0) return;
    state = FindState(
      open: true,
      query: state.query,
      matches: state.matches,
      current: (state.current + step) % n,
    );
    _reveal();
  }

  /// Scrolls the match that the user is at into view.
  void _reveal() {
    if (state.matches.isEmpty) return;
    final m = state.matches[state.current];
    if (!m.paragraph.attached) return;
    final boxes = m.paragraph.getBoxesForSelection(
        TextSelection(baseOffset: m.start, extentOffset: m.end));
    m.paragraph.showOnScreen(
      rect: boxes.isEmpty ? null : boxes.first.toRect().inflate(24),
      duration: const Duration(milliseconds: 150),
    );
  }

  @override
  void dispose() {
    focusRequests.dispose();
    super.dispose();
  }
}

/// The find state of the app.
final findProvider =
    StateNotifierProvider<FindController, FindState>((_) => FindController());

/// Puts the find bar and the marks over [child].
class FindHost extends ConsumerStatefulWidget {
  /// Creates the host.
  const FindHost({required this.child, super.key});

  /// The app. Its text is what the bar searches.
  final Widget child;

  @override
  ConsumerState<FindHost> createState() => _FindHostState();
}

class _FindHostState extends ConsumerState<FindHost> {
  final _content = GlobalKey();
  final _field = TextEditingController();
  final _focus = FocusNode(debugLabel: 'find field');
  Timer? _timer;
  final _repaint = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    final controller = ref.read(findProvider.notifier);
    controller.rootOf = () => _content.currentContext?.findRenderObject();
    controller.focusRequests.addListener(_takeFocus);
  }

  void _takeFocus() {
    _focus.requestFocus();
    _field
      ..text = ref.read(findProvider).query
      ..selection =
          TextSelection(baseOffset: 0, extentOffset: _field.text.length);
  }

  /// While the bar is open, search again a few times a second: the screen
  /// changes when data arrives or the window changes size. The marks follow
  /// the text when a list scrolls (see [build]).
  void _keepSearching(bool open) {
    if (open && _timer == null) {
      _timer = Timer.periodic(const Duration(milliseconds: 300), (_) {
        ref.read(findProvider.notifier).refresh();
        _repaint.value++;
      });
    } else if (!open) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _entry
      ..remove()
      ..dispose();
    _repaint.dispose();
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// The marks and the bar. They live in their own [Overlay]: the host sits
  /// above the navigator of the app, so no overlay of the app is above it, and
  /// the text field and the tooltips of the bar need one.
  late final OverlayEntry _entry = OverlayEntry(builder: _layer);

  Widget _layer(BuildContext context) => Consumer(builder: (context, ref, _) {
        final state = ref.watch(findProvider);
        if (!state.open) return const SizedBox.shrink();
        return Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  key: const Key('find-marks'),
                  painter: _MarksPainter(
                    state: state,
                    scheme: Theme.of(context).colorScheme,
                    repaint: _repaint,
                  ),
                ),
              ),
            ),
            Positioned(
              top: Space.md,
              right: Space.lg,
              child: Material(
                type: MaterialType.transparency,
                child: _FindBar(state: state, field: _field, focus: _focus),
              ),
            ),
          ],
        );
      });

  @override
  Widget build(BuildContext context) {
    _keepSearching(ref.watch(findProvider.select((s) => s.open)));
    return Stack(
      children: [
        Positioned.fill(
          child: NotificationListener<ScrollNotification>(
            // A list scrolls: draw the marks where the text is now.
            onNotification: (_) {
              _repaint.value++;
              return false;
            },
            child: KeyedSubtree(key: _content, child: widget.child),
          ),
        ),
        Positioned.fill(
          child: Overlay(clipBehavior: Clip.none, initialEntries: [_entry]),
        ),
      ],
    );
  }
}

class _MarksPainter extends CustomPainter {
  _MarksPainter(
      {required this.state, required this.scheme, required Listenable repaint})
      : super(repaint: repaint);

  final FindState state;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final other = Paint()..color = scheme.tertiary.withValues(alpha: 0.35);
    final here = Paint()..color = scheme.secondary.withValues(alpha: 0.6);
    for (var i = 0; i < state.matches.length; i++) {
      final paint = i == state.current ? here : other;
      for (final r in state.matches[i].screenRects()) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(r.inflate(1.5), const Radius.circular(3)),
            paint);
      }
    }
  }

  @override
  bool shouldRepaint(_MarksPainter old) =>
      old.state != state || old.scheme != scheme;
}

class _FindBar extends ConsumerWidget {
  const _FindBar(
      {required this.state, required this.field, required this.focus});

  final FindState state;
  final TextEditingController field;
  final FocusNode focus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(findProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final count = state.query.isEmpty
        ? ''
        : state.matches.isEmpty
            ? 'No matches'
            : '${state.current + 1} of ${state.matches.length}'
                '${state.matches.length >= maxFindMatches ? '+' : ''}';
    return Container(
      key: const Key('find-bar'),
      width: 360,
      padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(Corner.md),
        border: Border.all(color: context.tefteri.rule),
        boxShadow: [
          BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.18),
              blurRadius: 12,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.search, size: 18),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Focus(
              onKeyEvent: (node, event) {
                if (event is KeyUpEvent) return KeyEventResult.ignored;
                final key = event.logicalKey;
                if (key == LogicalKeyboardKey.escape) {
                  controller.close();
                  return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.enter ||
                    key == LogicalKeyboardKey.numpadEnter) {
                  HardwareKeyboard.instance.isShiftPressed
                      ? controller.previous()
                      : controller.next();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                key: const Key('find-field'),
                controller: field,
                focusNode: focus,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Find on this page',
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
                onChanged: controller.setQuery,
              ),
            ),
          ),
          Text(count, key: const Key('find-count'), style: text.bodySmall),
          IconButton(
            key: const Key('find-previous'),
            tooltip: 'Previous match (Shift+Enter)',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.keyboard_arrow_up),
            onPressed: state.matches.isEmpty ? null : controller.previous,
          ),
          IconButton(
            key: const Key('find-next'),
            tooltip: 'Next match (Enter)',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: state.matches.isEmpty ? null : controller.next,
          ),
          IconButton(
            key: const Key('find-close'),
            tooltip: 'Close (Esc)',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close),
            onPressed: controller.close,
          ),
        ],
      ),
    );
  }
}
