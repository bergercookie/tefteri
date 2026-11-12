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

/// The terms of the weekly picker, explained once at their first use.
const weeklyPickerTerms = [
  Term('Milestone', 'A small project you can finish in about a week.'),
  Term('Done-state', 'One sentence that says when a milestone is finished.'),
  Term('Committed', 'Chosen for this week\'s plan.'),
  Term('Parked', 'Set aside by a review. It comes back in this list later.'),
];

/// The terms of the weekly review.
const weeklyReviewTerms = [
  Term('Rollover', 'A milestone you recommit because it was not finished.'),
  Term('Parked', 'Set aside by a review. It comes back in the picker later.'),
  Term('Decide later', 'Changes nothing. The picker reminds you next time.'),
];

/// The three work categories, explained once at their first use.
const categoryTerms = [
  Term('Goal-aligned', 'Work in a milestone that was committed for the week.'),
  Term('Maintenance',
      'Work in a routine project, like chores or admin. You never plan it.'),
  Term('Off-plan', 'Goal work that was not committed for the week.'),
];

/// Unsorted tasks, explained when the first one shows.
const unsortedTaskTerms = [
  Term('Unsorted',
      'Its project has no label, or it has no project. Tefteri counts it as off-plan.'),
];

/// Hidden tasks, explained when the first ones show.
const hiddenTaskTerms = [
  Term('Hidden',
      'Tasks in ignored projects. They are not counted in any category.'),
];

/// The term for a milestone under a theme that is not in the month's focus.
const outsideFocusTerms = [
  Term('Outside focus',
      'Its theme is not one of the themes you chose for this month.'),
];

/// A closable box that lists [terms]. It shows until the user closes it.
///
/// With [compact] it starts as one tappable line that opens in place, so the
/// list below stays in view. The user can open or fold it either way.
class TermHint extends ConsumerStatefulWidget {
  /// Creates the hint; [id] is what the device remembers.
  const TermHint({
    required this.id,
    required this.title,
    required this.terms,
    this.compact = false,
    this.compactTitle,
    super.key,
  });

  /// Stable id of the hint.
  final String id;

  /// Heading of the box.
  final String title;

  /// The terms to explain.
  final List<Term> terms;

  /// Whether the hint is folded to one line until the user opens it.
  final bool compact;

  /// The text of the folded line; defaults to [title].
  final String? compactTitle;

  @override
  ConsumerState<TermHint> createState() => _TermHintState();
}

class _TermHintState extends ConsumerState<TermHint> {
  /// What the user chose by tapping; null follows [TermHint.compact].
  bool? _open;

  @override
  Widget build(BuildContext context) {
    final closed = ref.watch(closedHintsProvider).valueOrNull;
    // Wait for the stored state, so a closed hint does not flash.
    if (closed == null || closed.contains(widget.id)) {
      return const SizedBox.shrink();
    }
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final open = _open ?? !widget.compact;
    if (!open) {
      return Padding(
        padding: const EdgeInsets.only(bottom: Space.xs),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: Key('term-hint-open-${widget.id}'),
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: Space.sm),
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            onPressed: () => setState(() => _open = true),
            icon: const Icon(Icons.help_outline, size: 18),
            label: Text(widget.compactTitle ?? widget.title),
          ),
        ),
      );
    }
    final heading = Text(widget.title, style: text.titleSmall);
    return Container(
      key: Key('term-hint-${widget.id}'),
      margin: const EdgeInsets.only(bottom: Space.md),
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
                if (widget.compact)
                  InkWell(
                    key: Key('term-hint-fold-${widget.id}'),
                    onTap: () => setState(() => _open = false),
                    child: Row(children: [
                      Flexible(child: heading),
                      const SizedBox(width: Space.xs),
                      const Icon(Icons.expand_less, size: 18),
                    ]),
                  )
                else
                  heading,
                const SizedBox(height: Space.xs),
                for (final t in widget.terms)
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
            key: Key('term-hint-close-${widget.id}'),
            tooltip: 'Got it, hide this hint',
            icon: const Icon(Icons.close),
            onPressed: () =>
                ref.read(closedHintsProvider.notifier).close(widget.id),
          ),
        ],
      ),
    );
  }
}
