/// Empty and loading states in the house style.
library;

import 'package:flutter/material.dart';

import 'palette.dart';
import 'tokens.dart';

/// A short, quiet message with a small drawn page above it.
class EmptyState extends StatelessWidget {
  /// Creates the state. [messageKey] goes on the message text, for tests.
  const EmptyState({
    required this.message,
    this.messageKey,
    this.action,
    this.icon = Icons.edit_note_outlined,
    super.key,
  });

  /// What the user sees.
  final String message;

  /// Key of the message text.
  final Key? messageKey;

  /// An optional button under the message.
  final Widget? action;

  /// The picture above the message.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: scheme.surfaceContainer,
                shape: BoxShape.circle,
                border: Border.all(color: context.tefteri.rule),
              ),
              child: Icon(icon, size: 26, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: Space.md),
            Text(
              message,
              key: messageKey,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (action != null) ...[const SizedBox(height: Space.sm), action!],
          ],
        ),
      ),
    );
  }
}

/// A small, thin progress ring that replaces the default fat spinner.
class Loading extends StatelessWidget {
  /// Creates the indicator.
  const Loading({super.key});

  @override
  Widget build(BuildContext context) => const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
}
