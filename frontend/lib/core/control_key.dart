/// Tells whether the Ctrl key goes with a click.
library;

import 'package:flutter/foundation.dart' show visibleForTesting;
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
  static DateTime? _released;

  /// Ctrl is down, or went up a moment ago.
  static bool get heldRecently {
    final released = _released;
    return HardwareKeyboard.instance.isControlPressed ||
        (released != null && now().difference(released) < _grace);
  }

  /// Forgets when Ctrl went up. Tests call it before they move the clock.
  @visibleForTesting
  static void reset() => _released = null;

  /// Starts to watch the Ctrl keys. Call it before [heldRecently] is read. It
  /// may be called any number of times: the keyboard has the handler once.
  static void watch() {
    HardwareKeyboard.instance
      ..removeHandler(_onKey)
      ..addHandler(_onKey);
  }

  static bool _onKey(KeyEvent event) {
    if (event is KeyUpEvent &&
        (event.logicalKey == LogicalKeyboardKey.controlLeft ||
            event.logicalKey == LogicalKeyboardKey.controlRight)) {
      _released = now();
    }
    return false;
  }
}
