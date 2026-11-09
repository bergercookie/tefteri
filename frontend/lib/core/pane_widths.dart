/// The widths of the panes that the user can resize by dragging, and the
/// divider that does the dragging.
library;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/theme.dart';

/// The width of one pane. Drag changes it at once; [save] keeps it for the
/// next start, and [reset] goes back to [initial].
class PaneWidth extends StateNotifier<double> {
  /// Creates the width. [key] names the saved value.
  PaneWidth(this._key, this.initial, {required this.min, required this.max})
      : super(initial) {
    SharedPreferences.getInstance().then((p) {
      final saved = p.getDouble(_key);
      if (mounted && saved != null) state = saved.clamp(min, max);
    }, onError: (_) {}); // no saved width: keep the default
  }

  final String _key;

  /// The width before the user changes it.
  final double initial;

  /// The smallest width.
  final double min;

  /// The largest width.
  final double max;

  /// Sets the width, inside the limits.
  void set(double value) => state = value.clamp(min, max);

  /// Grows the width by [dx] pixels (shrinks it when negative). [cap] is the
  /// most that the window shows now: a width that the window cannot show
  /// starts from there, so the pane follows the pointer at once.
  void by(double dx, {double? cap}) {
    final base = cap == null ? state : (state < cap ? state : cap);
    set(base + dx);
  }

  /// Keeps the width for the next start.
  Future<void> save() async {
    try {
      await (await SharedPreferences.getInstance()).setDouble(_key, state);
    } on Object {
      // The width is only a convenience: ignore a store that does not work.
    }
  }

  /// Goes back to the width that the app starts with.
  Future<void> reset() {
    state = initial;
    return save();
  }
}

/// Width of the navigation sidebar when it shows labels.
final sidebarWidthProvider = StateNotifierProvider<PaneWidth, double>(
    (_) => PaneWidth('sidebar_width', 232, min: 200, max: 360));

/// Width of the task list in the planner.
final taskPaneWidthProvider = StateNotifierProvider<PaneWidth, double>(
    (_) => PaneWidth('task_pane_width', 360, min: 260, max: 640));

/// Width of the area that a [ResizeHandle] takes, with its line in the middle.
const double resizeHandleWidth = 10;

/// A thin vertical divider that the user drags to resize the pane at its left.
///
/// The pointer shows a resize cursor over it. With the keyboard, focus it and
/// press the left or right arrow key; Home (or a double click) restores the
/// standard width.
class ResizeHandle extends StatefulWidget {
  /// Creates the handle. [onDrag] gets the distance in pixels that the user
  /// moved (negative to the left); [onEnd] runs when the move ends;
  /// [onReset] restores the standard width.
  const ResizeHandle({
    required this.label,
    required this.onDrag,
    required this.onEnd,
    required this.onReset,
    super.key,
  });

  /// What the handle resizes, for screen readers: `Resize the sidebar`.
  final String label;

  /// The pane grew (positive) or shrank (negative) by this many pixels.
  final ValueChanged<double> onDrag;

  /// The move ended.
  final VoidCallback onEnd;

  /// The user asked for the standard width.
  final VoidCallback onReset;

  @override
  State<ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<ResizeHandle> {
  static const double _step = 16;
  bool _hover = false;
  bool _dragging = false;
  bool _focused = false;
  final _node = FocusNode(debugLabel: 'resize handle');

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      widget.onDrag(-_step);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      widget.onDrag(_step);
    } else if (key == LogicalKeyboardKey.home) {
      widget.onReset();
      return KeyEventResult.handled;
    } else {
      return KeyEventResult.ignored;
    }
    widget.onEnd();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = _hover || _dragging || _focused;
    return Semantics(
      label: widget.label,
      hint: 'Drag, or use the left and right arrow keys',
      child: Focus(
        focusNode: _node,
        onKeyEvent: _key,
        onFocusChange: (f) => setState(() => _focused = f),
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            // The pane follows the pointer from the first pixel, not from the
            // end of the drag slop.
            dragStartBehavior: DragStartBehavior.down,
            onTapDown: (_) => _node.requestFocus(),
            onHorizontalDragStart: (_) => setState(() => _dragging = true),
            onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
            onHorizontalDragEnd: (_) {
              setState(() => _dragging = false);
              widget.onEnd();
            },
            onHorizontalDragCancel: () => setState(() => _dragging = false),
            onDoubleTap: widget.onReset,
            child: SizedBox(
              width: resizeHandleWidth,
              child: Center(
                child: AnimatedContainer(
                  duration:
                      Motion.of(context, const Duration(milliseconds: 120)),
                  width: active ? 3 : 1,
                  color: active ? scheme.primary : context.tefteri.rule,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
