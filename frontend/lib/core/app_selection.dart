/// Makes the text of the whole app selectable.
library;

import 'package:flutter/material.dart';

/// Wraps [child] (the app's navigator) in one [SelectionArea].
///
/// A selection area needs an [Overlay] above it for the selection handles and
/// the copy menu, and the navigator is not above `MaterialApp.builder`. This
/// widget therefore brings its own overlay. Dialogs, menus and messages sit in
/// the navigator below, so their text can be selected too.
///
/// Draggable widgets exclude their own text with `SelectionContainer.disabled`,
/// because a drag on them moves the item.
class AppSelection extends StatefulWidget {
  /// Creates the wrapper.
  const AppSelection({required this.child, super.key});

  /// The navigator of the app.
  final Widget child;

  @override
  State<AppSelection> createState() => _AppSelectionState();
}

class _AppSelectionState extends State<AppSelection> {
  late final OverlayEntry _entry =
      OverlayEntry(builder: (_) => SelectionArea(child: widget.child));

  @override
  void didUpdateWidget(AppSelection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.child != widget.child) _entry.markNeedsBuild();
  }

  @override
  void dispose() {
    _entry.remove();
    _entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Overlay(initialEntries: [_entry]);
}
