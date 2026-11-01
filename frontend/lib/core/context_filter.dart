/// Global all/life/work filter shared by every view.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Work/life filter values; [name] matches the API's `context` parameter.
enum ContextFilter {
  /// Show everything.
  all,

  /// Personal items only.
  life,

  /// Work items only.
  work;

  /// Query parameters that every list or view request must send.
  Map<String, String> get queryParameters => {'context': name};
}

/// The currently selected filter.
final contextFilterProvider =
    StateProvider<ContextFilter>((_) => ContextFilter.all);

/// Small chip that tells the user an item has no work/life context yet.
class UnclassifiedMarker extends StatelessWidget {
  /// Creates the marker.
  const UnclassifiedMarker({super.key});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'No work or life context is set. It follows the app default.',
      child: Chip(
        key: const Key('unclassified-marker'),
        label: const Text('Unclassified'),
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        labelStyle: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

/// Shows an [UnclassifiedMarker] when [itemContext] is null; else nothing.
class ContextMarker extends StatelessWidget {
  /// Creates a marker for an item whose own context is [itemContext].
  const ContextMarker({required this.itemContext, super.key});

  /// The item's own `context` field (null when not classified).
  final String? itemContext;

  @override
  Widget build(BuildContext context) => itemContext == null
      ? const UnclassifiedMarker()
      : const SizedBox.shrink();
}
