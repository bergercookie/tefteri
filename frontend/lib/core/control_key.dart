/// Tells whether the Ctrl key goes with a click, and spots a double click that
/// holds it.
library;

import 'package:flutter/services.dart';

/// The Ctrl key, as the clicks of a task see it.
///
/// On the web with the accessibility tree on (it is on for the whole app),
/// Flutter holds a pointer event for a short time before it hands it to the
/// app. A quick Ctrl and click can end before that, so Ctrl is already up when
/// the click arrives. [heldRecently] counts a Ctrl that went up a moment ago.
class ControlKey {
  ControlKey._();

  /// The clock. Tests set it to move time on.
  static DateTime Function() now = DateTime.now;

  static const _grace = Duration(milliseconds: 600);
  static const _doubleClick = Duration(milliseconds: 600);
  static DateTime? _released;
  static bool _listening = false;
  static String? _lastTap;
  static DateTime? _lastTapAt;

  /// Ctrl is down, or went up a moment ago.
  static bool get heldRecently {
    final released = _released;
    return HardwareKeyboard.instance.isControlPressed ||
        (released != null && now().difference(released) < _grace);
  }

  /// Starts to watch the Ctrl keys. Call it before [heldRecently] is read.
  static void watch() {
    if (_listening) return;
    _listening = true;
    HardwareKeyboard.instance.addHandler((event) {
      if (event is KeyUpEvent &&
          (event.logicalKey == LogicalKeyboardKey.controlLeft ||
              event.logicalKey == LogicalKeyboardKey.controlRight)) {
        _released = now();
      }
      return false;
    });
  }

  /// Call it for a click that holds Ctrl, with the id of what was clicked.
  /// Answers true when this is the second such click on the same thing within
  /// a short time: a Ctrl and double click.
  ///
  /// It counts the clicks itself, because a double-click recognizer would
  /// delay every single click, and the accessibility tree of the web client
  /// turns clicks into taps that have no double-tap form.
  static bool isSecondClick(String id) {
    final at = now();
    final last = _lastTapAt;
    final second =
        _lastTap == id && last != null && at.difference(last) < _doubleClick;
    // A third click starts a new pair.
    _lastTap = second ? null : id;
    _lastTapAt = second ? null : at;
    return second;
  }
}
