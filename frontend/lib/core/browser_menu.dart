/// Keeps the menu of the browser away from a right click that the app uses.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Turns the context menu of the browser off while the pointer is over
/// [child], so that a right click on it opens the menu of the app and not
/// both. Elsewhere the browser keeps its own menu. It does nothing outside
/// the web.
class NoBrowserMenu extends StatelessWidget {
  /// Creates the wrapper.
  const NoBrowserMenu({required this.child, super.key});

  /// The area in which a right click belongs to the app.
  final Widget child;

  static void _set(bool enabled) {
    if (!kIsWeb) return;
    if (enabled) {
      BrowserContextMenu.enableContextMenu();
    } else {
      BrowserContextMenu.disableContextMenu();
    }
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => _set(false),
        onExit: (_) => _set(true),
        child: child,
      );
}
