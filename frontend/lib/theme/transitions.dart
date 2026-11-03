/// Page transition: a short fade with a small rise.
library;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// Fades the new page in while it moves up by a few pixels. With reduced
/// motion the page just appears.
class SoftPageTransitionsBuilder extends PageTransitionsBuilder {
  /// Creates the builder.
  const SoftPageTransitionsBuilder();

  @override
  Duration get transitionDuration => Motion.page;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final curved = CurvedAnimation(parent: animation, curve: Motion.enter);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.012), end: Offset.zero)
            .animate(curved),
        child: child,
      ),
    );
  }
}
