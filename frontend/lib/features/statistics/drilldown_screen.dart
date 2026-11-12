/// The tasks behind a count: opens from a count, a bar segment or the hidden
/// line of the category card.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/planning_models.dart';
import '../../core/shell.dart';
import '../../theme/theme.dart';
import '../../core/periods.dart';
import '../weekly/weekly_widgets.dart';
import 'category_style.dart';
import 'category_task_list.dart';
import 'statistics_models.dart';
import 'statistics_providers.dart';

const _periods = ['week', 'month', 'year'];

/// The address of the list for [category] (null: the three work categories)
/// in the [period] named by [day] (`YYYY-MM-DD`).
String drilldownLocation(String period, String day, Category? category) =>
    Uri(path: '/statistics', queryParameters: {
      'period': period,
      'day': day,
      if (category != null) 'category': category.json,
    }).toString();

/// Opens the list. It is pushed, so back returns to the card. Does nothing
/// without a router (tests of single widgets).
void openDrilldown(
        BuildContext context, String period, String day, Category? category) =>
    GoRouter.maybeOf(context)?.push(drilldownLocation(period, day, category));

/// The route `/statistics?period=&day=&category=&order=`.
GoRoute statisticsRoute() => GoRoute(
      path: '/statistics',
      builder: (_, s) => DrilldownScreen.fromQuery(s.uri.queryParameters),
    );

/// Lists the completed tasks of one category (or all three) in one period.
class DrilldownScreen extends StatefulWidget {
  /// Creates the screen. [day] is a `YYYY-MM-DD` key inside the period.
  const DrilldownScreen({
    required this.period,
    required this.day,
    required this.category,
    this.order = 'project',
    this.invalid = false,
    super.key,
  });

  /// Reads the parts of the address. A part that makes no sense shows a
  /// message with a way back instead of a list.
  factory DrilldownScreen.fromQuery(Map<String, String> q) {
    final period = q['period'] ?? 'week';
    final cat = q['category'];
    final category = Category.tryParse(cat);
    final day = q['day'] ?? dateKey(DateTime.now());
    return DrilldownScreen(
      period: period,
      day: DateTime.tryParse(day) == null ? '' : day,
      category: category,
      order: q['order'] ?? 'project',
      invalid: cat != null && category == null,
    );
  }

  /// `week`, `month` or `year`.
  final String period;

  /// A day of the period.
  final String day;

  /// The category, or null for the three work categories.
  final Category? category;

  /// `project` (grouped) or `newest`.
  final String order;

  /// The address had a category that is not known.
  final bool invalid;

  @override
  State<DrilldownScreen> createState() => _DrilldownScreenState();
}

class _DrilldownScreenState extends State<DrilldownScreen> {
  late String _order = widget.order;

  bool get _valid =>
      !widget.invalid &&
      _periods.contains(widget.period) &&
      DateTime.tryParse(widget.day) != null &&
      (widget.order == 'project' || widget.order == 'newest');

  String get _back {
    final day = _valid ? widget.day : dateKey(DateTime.now());
    return switch (widget.period) {
      'month' => '/month?date=$day',
      'year' => '/year?date=$day',
      _ => '/week?date=$day',
    };
  }

  String _periodName() {
    final d = DateTime.parse(widget.day);
    return switch (widget.period) {
      'month' => '${monthName(d.month)} ${d.year}',
      'year' => '${d.year}',
      _ => weekTitle(weekStartOf(d)),
    };
  }

  @override
  Widget build(BuildContext context) {
    if (!_valid) {
      return AppShell(
        title: 'Completed tasks',
        backTo: _back,
        body: const EmptyState(message: 'This list cannot be opened.'),
      );
    }
    final key = periodDayKey(widget.period, DateTime.parse(widget.day));
    final category = widget.category;
    final text = Theme.of(context).textTheme;
    final quiet = text.bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    final query = TaskListQuery(
        period: widget.period, day: key, category: category, order: _order);
    return AppShell(
      title: 'Completed tasks',
      backTo: _back,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  key: const Key('drilldown-title'),
                  spacing: Space.md,
                  runSpacing: Space.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (category != null)
                      CategoryBadge(category: category)
                    else
                      Text('All three categories', style: text.titleMedium),
                    Text(_periodName(), style: text.titleMedium),
                  ],
                ),
                const SizedBox(height: Space.xs),
                if (category == Category.hidden)
                  Text(
                    'These tasks are in ignored projects. They are not '
                    'counted in any category.',
                    style: quiet,
                  ),
                Text(
                  'This is a live list: it shows the tasks as of the last '
                  'sync. A task that was deleted or opened again no longer '
                  'shows, so this list can be shorter than the count on the '
                  'card.',
                  key: const Key('live-note'),
                  style: quiet,
                ),
                const SizedBox(height: Space.sm),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                        value: 'project',
                        label: Text('By project', key: Key('order-project'))),
                    ButtonSegment(
                        value: 'newest',
                        label: Text('Newest first', key: Key('order-newest'))),
                  ],
                  selected: {_order},
                  onSelectionChanged: (s) => setState(() => _order = s.first),
                ),
              ],
            ),
          ),
          Expanded(child: CategoryTaskList(query: query, scrollable: true)),
        ],
      ),
    );
  }
}
