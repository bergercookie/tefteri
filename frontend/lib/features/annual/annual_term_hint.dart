/// One-line hints that explain the words of annual planning once, at their
/// first use (FR-035). A hint shows one time, and a closed hint stays closed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/theme.dart';
import '../projects/term_hint.dart';

/// The words of annual planning that get a hint.
enum AnnualTerm {
  /// "Planning year".
  planningYear('Planning year',
      'The calendar year that your goals, key results and theme links belong to.'),

  /// "Key result".
  keyResult('Key result',
      'A number or a yes/no answer that shows whether a goal is met. A goal has one to three.'),

  /// "Theme project".
  themeProject('Theme project',
      'A long-running project in your task app, labelled theme. Link the themes whose work serves this key result.'),

  /// "Retire".
  retire('Retire',
      'Stop counting it as active. Its links end, but its history stays, and you can undo or restore it.'),

  /// "Unmet".
  unmet('Unmet',
      'The last value of a key result did not reach its target. Only unmet key results are suggested again.');

  const AnnualTerm(this.word, this.sentence);

  /// The word as the user sees it.
  final String word;

  /// What it means.
  final String sentence;

  /// The id that the device remembers.
  String get hintId => 'annual-$name';
}

/// A quiet, closable line that explains [term]. It hides itself once the
/// user has closed it on this device.
class AnnualTermHint extends ConsumerStatefulWidget {
  /// Creates the hint.
  const AnnualTermHint(this.term, {super.key});

  /// The word to explain.
  final AnnualTerm term;

  @override
  ConsumerState<AnnualTermHint> createState() => _AnnualTermHintState();
}

class _AnnualTermHintState extends ConsumerState<AnnualTermHint> {
  /// This hint was shown, and the store knows it.
  bool _marked = false;

  @override
  Widget build(BuildContext context) {
    final term = widget.term;
    final closed = ref.watch(closedHintsProvider).valueOrNull;
    if (closed == null || closed.contains(term.hintId)) {
      return const SizedBox.shrink();
    }
    if (!_marked) {
      // It shows now, and it shows only this once.
      _marked = true;
      final store = ref.read(closedHintsProvider.notifier);
      WidgetsBinding.instance
          .addPostFrameCallback((_) => store.markSeen(term.hintId));
    }
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      key: Key('annual-hint-${term.name}'),
      margin: const EdgeInsets.only(bottom: Space.sm),
      padding:
          const EdgeInsets.fromLTRB(Space.md, Space.xs, Space.xs, Space.xs),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border(left: BorderSide(color: scheme.primary, width: 3)),
        borderRadius: BorderRadius.circular(Corner.sm),
      ),
      child: Row(
        children: [
          Icon(Icons.lightbulb_outline,
              size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(
                  text: '${term.word}: ',
                  style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
              TextSpan(text: term.sentence, style: text.bodySmall),
            ])),
          ),
          IconButton(
            key: Key('annual-hint-close-${term.name}'),
            tooltip: 'Got it, hide this hint',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close),
            onPressed: () =>
                ref.read(closedHintsProvider.notifier).close(term.hintId),
          ),
        ],
      ),
    );
  }
}
