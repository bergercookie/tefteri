/// A hint that explains terms once, at their first use. It shows one time:
/// when the user has seen it, on any device, it stays away. The settings can
/// bring every hint back.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/planning_api.dart';
import '../../theme/theme.dart';

const _prefix = 'term_hint_closed_';

/// How long a seen hint waits before it is sent to the server. Hints that are
/// seen together (a page with several) go in one run, and a quick visit does not
/// start a call for each.
const _syncDelay = Duration(seconds: 1);

/// How long the start waits for the server's list of seen hints. A slow
/// server must not keep every hint away.
const _serverWait = Duration(seconds: 3);

/// The ids of the hints that stay away.
///
/// A hint is seen the first time that it is shown, and it is also seen when
/// the user closes it. The ids are kept in the settings of the user on the
/// server, so that a hint shows once for the user and not once for each
/// browser, and in this device's storage, which answers at once and also when
/// the server cannot. The state is what was stored when the app started, plus
/// the hints closed since: a hint that is shown for the first time does not
/// vanish from under the reader when its page builds again.
class ClosedHints extends StateNotifier<AsyncValue<Set<String>>> {
  /// Creates the store and reads the seen hints.
  ClosedHints(this._read) : super(const AsyncLoading()) {
    _load();
  }

  final PlanningApi Function() _read;

  /// Ends the wait for the server when the store goes away first.
  Timer? _wait;

  /// Starts the next run that tells the server about the seen hints.
  Timer? _sync;

  /// The hints that this device knows and the server may not.
  final Set<String> _unsent = {};

  Future<void> _load() async {
    final ids = <String>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in prefs.getKeys()) {
        if (k.startsWith(_prefix) && (prefs.getBool(k) ?? false)) {
          ids.add(k.substring(_prefix.length));
        }
      }
    } catch (_) {
      // No storage on this device: the server's list is all there is.
    }
    // The store may be gone while this device's storage answered.
    if (!mounted) return;
    // Ask the server, but not for longer than _serverWait. When it does not
    // answer, this device's list is used.
    final answered = Completer<void>();
    _wait = Timer(_serverWait, () {
      if (!answered.isCompleted) answered.complete();
    });
    try {
      _read().settings().then((settings) {
        if (!answered.isCompleted) ids.addAll(settings.seenHints);
      }).catchError((Object _) {
        // The server did not answer.
      }).whenComplete(() {
        if (!answered.isCompleted) answered.complete();
      });
    } catch (_) {
      // The server cannot even be asked.
      if (!answered.isCompleted) answered.complete();
    }
    await answered.future;
    _wait?.cancel();
    if (mounted) state = AsyncData({...ids});
  }

  @override
  void dispose() {
    _wait?.cancel();
    _sync?.cancel();
    super.dispose();
  }

  /// Remembers that hint [id] was shown, without hiding it now. It stays away
  /// the next time that the app starts, on every device. This device knows at
  /// once; the server is told a moment later.
  Future<void> markSeen(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_prefix$id', true);
    } catch (_) {
      // The server still keeps it.
    }
    if (!mounted) return;
    _unsent.add(id);
    _sync ??= Timer(_syncDelay, _send);
  }

  /// Tells the server about the hints that it has not heard of yet.
  Future<void> _send() async {
    _sync = null;
    final ids = _unsent.toList();
    _unsent.clear();
    for (final id in ids) {
      try {
        await _read().markHintSeen(id);
      } catch (_) {
        // This device keeps it, and it tells the server again next time.
      }
    }
  }

  /// The user closed hint [id]: it goes away now, and stays away.
  Future<void> close(String id) async {
    state = AsyncData({...?state.valueOrNull, id});
    await markSeen(id);
  }

  /// Brings every hint back: they show once again, here and on every device.
  Future<void> reset() async {
    _sync?.cancel();
    _sync = null;
    _unsent.clear();
    state = const AsyncData({});
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in prefs.getKeys().toList()) {
        if (k.startsWith(_prefix)) await prefs.remove(k);
      }
    } catch (_) {
      // The server's list is cleared below.
    }
    try {
      await _read().resetHints();
    } catch (_) {
      // Nothing more to do: this device's list is empty.
    }
  }
}

/// The hints that stay away.
final closedHintsProvider =
    StateNotifierProvider<ClosedHints, AsyncValue<Set<String>>>(
        (ref) => ClosedHints(() => ref.read(planningApiProvider)));

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

/// Terms used on the monthly planning screen.
const monthlyFocusTerms = [
  Term('Theme project', 'A long-running home for related work.'),
  Term('Milestone project',
      'A small outcome that you can finish in about a week.'),
  Term('Monthly focus',
      'The theme projects you choose for this month, each with a milestone target.'),
  Term('Key result', 'A measurable result linked to an annual goal.'),
];

/// Terms used on the monthly review screen.
const monthlyReviewTerms = [
  Term('Review snapshot',
      'A saved version of this review. It keeps its names and numbers.'),
  Term('Outside focus',
      'A finished milestone whose theme was not in this month’s focus.'),
  Term('Work categories',
      'Goal-aligned, maintenance and off-plan work, counted by the server.'),
  Term('Key result', 'A measurable result linked to an annual goal.'),
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

  /// This hint was shown, and the store knows it.
  bool _marked = false;

  @override
  Widget build(BuildContext context) {
    final closed = ref.watch(closedHintsProvider).valueOrNull;
    // Wait for the stored state, so a closed hint does not flash.
    if (closed == null || closed.contains(widget.id)) {
      return const SizedBox.shrink();
    }
    if (!_marked) {
      // It shows now, and it shows only this once: the next start keeps it away.
      _marked = true;
      final store = ref.read(closedHintsProvider.notifier);
      WidgetsBinding.instance
          .addPostFrameCallback((_) => store.markSeen(widget.id));
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
