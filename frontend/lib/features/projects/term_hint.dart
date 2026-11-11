/// A hint that explains terms once, at their first use, and stays away after
/// the user has closed it on this device.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/theme.dart';

const _prefix = 'term_hint_closed_';

/// Ids of the hints the user has closed on this device. A device without
/// storage simply shows the hints again.
class ClosedHints extends StateNotifier<AsyncValue<Set<String>>> {
  /// Creates the store and reads the closed hints.
  ClosedHints() : super(const AsyncLoading()) {
    _read();
  }

  Future<void> _read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = {
        for (final k in prefs.getKeys())
          if (k.startsWith(_prefix) && (prefs.getBool(k) ?? false))
            k.substring(_prefix.length),
      };
      if (mounted) state = AsyncData(ids);
    } catch (_) {
      if (mounted) state = const AsyncData({});
    }
  }

  /// Remembers that hint [id] is closed.
  Future<void> close(String id) async {
    state = AsyncData({...?state.valueOrNull, id});
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_prefix$id', true);
    } catch (_) {
      // The hint stays closed for this visit.
    }
  }
}

/// The closed hints of this device.
final closedHintsProvider =
    StateNotifierProvider<ClosedHints, AsyncValue<Set<String>>>(
        (_) => ClosedHints());

/// One term and its plain sentence.
@immutable
class Term {
  /// Creates a term.
  const Term(this.word, this.sentence);

  /// The word, for example `Routine (maintenance)`.
  final String word;

  /// What it means.
  final String sentence;
}

/// The terms of the Projects screen, in the words the user sees.
const projectTerms = [
  Term('Theme', 'A long-running home for related work.'),
  Term('Milestone', 'A small outcome you can finish in about a week.'),
  Term('Routine (maintenance)',
      'Work that repeats and never finishes, like chores or admin.'),
  Term('Ignored', 'Hidden from planning. It still syncs.'),
  Term('Unsorted', 'Not labelled yet. Tefteri shows its suggestion.'),
  Term('No longer in your task app',
      'Deleted or archived. Tefteri keeps its name, label and history.'),
];

/// A closable box that lists [terms]. It shows until the user closes it.
class TermHint extends ConsumerWidget {
  /// Creates the hint; [id] is what the device remembers.
  const TermHint(
      {required this.id, required this.title, required this.terms, super.key});

  /// Stable id of the hint.
  final String id;

  /// Heading of the box.
  final String title;

  /// The terms to explain.
  final List<Term> terms;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final closed = ref.watch(closedHintsProvider).valueOrNull;
    // Wait for the stored state, so a closed hint does not flash.
    if (closed == null || closed.contains(id)) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: Key('term-hint-$id'),
      margin: const EdgeInsets.only(bottom: Space.lg),
      padding:
          const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.sm, Space.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border(left: BorderSide(color: scheme.primary, width: 3)),
        borderRadius: BorderRadius.circular(Corner.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleSmall),
                const SizedBox(height: Space.xs),
                for (final t in terms)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.xs),
                    child: Text.rich(TextSpan(children: [
                      TextSpan(
                          text: '${t.word}: ',
                          style: text.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      TextSpan(text: t.sentence, style: text.bodyMedium),
                    ])),
                  ),
              ],
            ),
          ),
          IconButton(
            key: Key('term-hint-close-$id'),
            tooltip: 'Got it, hide this hint',
            icon: const Icon(Icons.close),
            onPressed: () => ref.read(closedHintsProvider.notifier).close(id),
          ),
        ],
      ),
    );
  }
}
