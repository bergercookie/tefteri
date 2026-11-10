/// Drag source used by the task list and the calendar blocks.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/theme.dart';
import 'planner_providers.dart';

/// Wraps [child] so that it can be dragged with [data].
///
/// Touch screens need a long press so that a swipe still scrolls. Mouse and
/// keyboard platforms start the drag at once. The feedback is anchored at the
/// pointer, so the drop target reads the position of the pointer.
class PlannerDraggable<T extends Object> extends ConsumerWidget {
  /// Creates a drag source.
  const PlannerDraggable({
    required this.data,
    required this.child,
    required this.label,
    this.dimmed = false,
    this.feedbackColor,
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

  /// Background of the chip that follows the pointer. The task color if null.
  final Color? feedbackColor;

  bool get _touch =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.read(dragActiveProvider.notifier);
    final preview = ref.read(dropPreviewProvider.notifier);
    // Read the notifiers now: the widget can be gone when the drag ends.
    void started() => active.state = true;
    void ended(DraggableDetails _) {
      active.state = false;
      preview.state = null;
    }

    final colors = context.tefteri;
    // The chip is painted below and to the right of the pointer, so that it
    // does not hide the slot that the calendar highlights under the pointer.
    // Only the painting moves: the drop still reads the pointer position.
    final feedback = Transform.translate(
      offset: const Offset(14, 26),
      child: Material(
        elevation: 4,
        color: feedbackColor ?? colors.taskContainer,
        borderRadius: BorderRadius.circular(Corner.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium),
          ),
        ),
      ),
    );
    // A drag on this widget moves the task. It must not also start a text
    // selection, so the text inside is not selectable.
    final content = SelectionContainer.disabled(child: child);
    final shown = Opacity(opacity: dimmed ? 0.5 : 1, child: content);
    final ghost = Opacity(opacity: 0.4, child: content);
    if (_touch) {
      return LongPressDraggable<T>(
        data: data,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: feedback,
        childWhenDragging: ghost,
        onDragStarted: started,
        onDragEnd: ended,
        child: shown,
      );
    }
    return Draggable<T>(
      data: data,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: feedback,
      childWhenDragging: ghost,
      onDragStarted: started,
      onDragEnd: ended,
      child: shown,
    );
  }
}
