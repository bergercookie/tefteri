/// Hover effect that shows a task row can be dragged.
library;

import 'package:flutter/material.dart';

import '../../theme/theme.dart';

/// Scale of a row while the pointer is over it.
const double hoverScale = 1.015;

/// Duration of the hover animation.
const Duration hoverDuration = Duration(milliseconds: 150);

/// Wraps a draggable row. When the mouse pointer is over the row, the row
/// lifts (a soft shadow, a colored outline and a small zoom), a grip appears
/// and the cursor becomes an open hand. Touch screens have no hover, so they
/// show the hint text of the task pane instead.
class HoverLift extends StatefulWidget {
  /// Creates the effect around [child]; [id] is used for widget keys.
  const HoverLift({required this.id, required this.child, super.key});

  /// Id of the task, for the keys of the animated parts.
  final String id;

  /// The row.
  final Widget child;

  @override
  State<HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<HoverLift> {
  bool _hover = false;

  void _set(bool value) {
    if (_hover != value) setState(() => _hover = value);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // People who turn animations off get the same change without motion.
    final duration =
        MediaQuery.disableAnimationsOf(context) ? Duration.zero : hoverDuration;
    return MouseRegion(
      cursor: _hover ? SystemMouseCursors.grab : MouseCursor.defer,
      onEnter: (_) => _set(true),
      onExit: (_) => _set(false),
      child: AnimatedScale(
        key: Key('task-hover-${widget.id}'),
        scale: _hover ? hoverScale : 1,
        duration: duration,
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: duration,
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: _hover
                ? scheme.primaryContainer.withValues(alpha: 0.35)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(Corner.md),
            border: Border.all(
              color: _hover ? scheme.primary : Colors.transparent,
            ),
            boxShadow: [
              if (_hover)
                BoxShadow(
                  color: scheme.shadow.withValues(alpha: 0.18),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
            ],
          ),
          child: Row(
            children: [
              // The grip keeps its space, so the text does not jump.
              AnimatedOpacity(
                key: Key('drag-handle-${widget.id}'),
                opacity: _hover ? 1 : 0,
                duration: duration,
                child: Icon(Icons.drag_indicator,
                    size: 18, color: scheme.onSurfaceVariant),
              ),
              Expanded(child: widget.child),
            ],
          ),
        ),
      ),
    );
  }
}
