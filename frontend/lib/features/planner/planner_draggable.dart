/// Drag source used by the task list and the calendar blocks.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Wraps [child] so that it can be dragged with [data].
///
/// Touch screens need a long press so that a swipe still scrolls. Mouse and
/// keyboard platforms start the drag at once. The feedback is anchored at the
/// pointer, so the drop target reads the position of the pointer.
class PlannerDraggable<T extends Object> extends StatelessWidget {
  /// Creates a drag source.
  const PlannerDraggable({
    required this.data,
    required this.child,
    required this.label,
    this.dimmed = false,
    super.key,
  });

  /// What a drop target receives.
  final T data;

  /// The draggable content.
  final Widget child;

  /// Short text on the drag feedback.
  final String label;

  /// Shows the source dimmed (a save is running).
  final bool dimmed;

  bool get _touch =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Widget build(BuildContext context) {
    final feedback = Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
    final shown = Opacity(opacity: dimmed ? 0.5 : 1, child: child);
    final ghost = Opacity(opacity: 0.4, child: child);
    if (_touch) {
      return LongPressDraggable<T>(
        data: data,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: feedback,
        childWhenDragging: ghost,
        child: shown,
      );
    }
    return Draggable<T>(
      data: data,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: feedback,
      childWhenDragging: ghost,
      child: shown,
    );
  }
}
