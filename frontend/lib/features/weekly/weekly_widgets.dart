/// Small widgets and helpers shared by the steps of the weekly planning.
library;

import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import '../goals/periods.dart';
import 'weekly_api.dart';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// `Mon` for a Monday.
String dayName(DateTime d) => _weekdays[d.weekday - 1];

/// `Mon 9 Nov`.
String dayLong(DateTime d) => '${dayName(d)} ${d.day} ${monthName(d.month)}';

/// `Week of 9 Nov`.
String weekTitle(DateTime start) =>
    'Week of ${start.day} ${monthName(start.month)}';

/// `the week of 9 Nov`, for use inside a sentence.
String weekPhrase(DateTime start) =>
    'the week of ${start.day} ${monthName(start.month)}';

/// `project` for 1, `projects` otherwise (a counter label).
String noun(int n, String one, [String? many]) =>
    n == 1 ? one : (many ?? '${one}s');

/// `1 task`, `3 tasks`.
String plural(int n, String one, [String? many]) =>
    '$n ${n == 1 ? one : (many ?? '${one}s')}';

/// The week to plan when the page opens: this week on a Monday, else the
/// coming one.
DateTime defaultPlanningWeek(DateTime now) {
  final monday = weekStartOf(now);
  return now.weekday == DateTime.monday
      ? monday
      : DateTime(monday.year, monday.month, monday.day + 7);
}

/// What the step widgets can ask the screen to do.
class WeeklyActions {
  /// Creates the actions.
  const WeeklyActions({
    required this.week,
    required this.run,
    required this.setDay,
    required this.openUrl,
    required this.changePlan,
  });

  /// Monday of the planned week, `YYYY-MM-DD`.
  final String week;

  /// Runs a change that answers with the new state; the screen shows the
  /// error message when it fails.
  final Future<bool> Function(Future<dynamic> Function(WeeklyApi api) call) run;

  /// Gives a task a day (null: no day).
  final Future<void> Function(String taskId, DateTime? day) setDay;

  /// Opens a page of the task app.
  final void Function(String url) openUrl;

  /// Makes a committed plan editable again.
  final VoidCallback changePlan;
}

/// A row that wraps on narrow screens and, when it fits, puts its first child
/// at the start and its last at the end.
class SpreadRow extends StatelessWidget {
  /// Creates the row.
  const SpreadRow({
    required this.children,
    this.alignment = WrapAlignment.spaceBetween,
    super.key,
  });

  /// The widgets of the row.
  final List<Widget> children;

  /// How the children share the free space.
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: alignment,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: Space.sm,
          children: children,
        ),
      );
}

/// A heading with a short line under it.
class StepHeading extends StatelessWidget {
  /// Creates the heading.
  const StepHeading({required this.title, this.subtitle, super.key});

  /// The heading.
  final String title;

  /// The line under it.
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.headlineSmall),
          if (subtitle != null) ...[
            const SizedBox(height: Space.xs),
            Text(subtitle!, style: text.bodyMedium),
          ],
        ],
      ),
    );
  }
}

/// A big number with a label, for the committed and done counters.
class Counter extends StatelessWidget {
  /// Creates the counter.
  const Counter(
      {required this.label, required this.value, this.accent, super.key});

  /// What is counted.
  final String label;

  /// The number.
  final int value;

  /// Color of the number.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$value',
            style: text.displaySmall?.copyWith(
                color: accent ?? Theme.of(context).colorScheme.onSurface)),
        Text(label, style: text.bodySmall),
      ],
    );
  }
}

/// A tinted note with an icon, for what the user should do next.
class Notice extends StatelessWidget {
  /// Creates the note.
  const Notice({required this.message, this.icon, this.actions, super.key});

  /// The text.
  final String message;

  /// The icon before the text.
  final IconData? icon;

  /// Buttons under the text.
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.tefteri;
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colors.taskContainer,
        borderRadius: BorderRadius.circular(Corner.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: colors.task),
            const SizedBox(width: Space.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message, style: Theme.of(context).textTheme.bodyMedium),
                if (actions != null) ...[
                  const SizedBox(height: Space.sm),
                  Wrap(spacing: Space.sm, children: actions!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The buttons under a step: back, and the main way forward.
class StepFooter extends StatelessWidget {
  /// Creates the footer.
  const StepFooter({
    required this.nextLabel,
    required this.onNext,
    this.onBack,
    this.hint,
    super.key,
  });

  /// Text of the forward button.
  final String nextLabel;

  /// Called by the forward button; null disables it.
  final VoidCallback? onNext;

  /// Called by the back button; null hides it.
  final VoidCallback? onBack;

  /// A line that says why the forward button is off.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SpreadRow(
            alignment:
                onBack == null ? WrapAlignment.end : WrapAlignment.spaceBetween,
            children: [
              if (onBack != null)
                TextButton.icon(
                  key: const Key('step-back'),
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('Back'),
                ),
              FilledButton(
                key: const Key('step-next'),
                onPressed: onNext,
                child: Text(nextLabel),
              ),
            ],
          ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(hint!,
                    key: const Key('step-hint'),
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            ),
        ],
      ),
    );
  }
}
