/// Page Up and Page Down for the view that is on screen.
///
/// Flutter's own Page Up and Page Down scroll the list that holds the keyboard
/// focus. In tefteri the focus is usually on the root of the app, above every
/// view, so the keys found no list and did nothing. [pageScroll] scrolls the
/// list that the user is looking at instead.
library;

import 'package:flutter/material.dart';

/// Scrolls the vertical list of the view below [root] by one page.
///
/// The list that holds the keyboard focus goes first, when there is one.
/// Otherwise it is the list with the largest visible area that has more to
/// scroll in the wanted [forward] direction: the content of the view, not the
/// navigation drawer. Returns false when nothing could scroll.
bool pageScroll(BuildContext root, {required bool forward}) {
  final focus = FocusManager.instance.primaryFocus?.context;
  final focused = focus == null ? null : Scrollable.maybeOf(focus);
  final candidates = <ScrollableState>[
    if (focused != null) focused,
    ..._visibleScrollables(root),
  ];
  for (final state in candidates) {
    if (_scrollPage(state, forward)) return true;
  }
  return false;
}

/// Moves [state] by one page, less a small overlap so the user keeps their
/// place. False when it is not vertical or is already at that end.
bool _scrollPage(ScrollableState state, bool forward) {
  final position = state.position;
  if (position.axis != Axis.vertical || !position.hasContentDimensions) {
    return false;
  }
  final room = forward
      ? position.maxScrollExtent - position.pixels
      : position.pixels - position.minScrollExtent;
  if (room <= 0.5) return false;
  final page = position.viewportDimension * 0.9;
  final target = (position.pixels + (forward ? page : -page))
      .clamp(position.minScrollExtent, position.maxScrollExtent);
  position.animateTo(
    target,
    duration: const Duration(milliseconds: 150),
    curve: Curves.easeOut,
  );
  return true;
}

/// The vertical lists below [root] that are on screen and can scroll, the
/// one with the largest area first.
List<ScrollableState> _visibleScrollables(BuildContext root) {
  final found = <(ScrollableState, double)>[];
  void visit(Element element) {
    final widget = element.widget;
    // A route that is covered by another one is kept in the tree but hidden.
    if (widget is Offstage && widget.offstage) return;
    if (element is StatefulElement && element.state is ScrollableState) {
      final state = element.state as ScrollableState;
      final box = element.renderObject;
      if (box is RenderBox &&
          box.hasSize &&
          state.position.hasContentDimensions &&
          state.position.axis == Axis.vertical &&
          state.position.maxScrollExtent > state.position.minScrollExtent) {
        found.add((state, box.size.width * box.size.height));
      }
    }
    element.visitChildren(visit);
  }

  (root as Element).visitChildren(visit);
  found.sort((a, b) => b.$2.compareTo(a.$2));
  return [for (final f in found) f.$1];
}
