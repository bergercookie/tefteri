/// The tasks that are still to do in one work category: opens from a count or
/// a bar segment of the card Still to do.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_error.dart';
import '../../core/periods.dart';
import '../../core/planning_api.dart';
import '../../core/planning_models.dart';
import '../../core/shell.dart';
import '../../theme/theme.dart';
import '../weekly/weekly_widgets.dart';
import 'category_style.dart';
import 'open_task_row.dart';
import 'statistics_models.dart';
import 'statistics_providers.dart';

/// The address of the list of open tasks of [category] in the week named by
/// [day] (`YYYY-MM-DD`).
String openDrilldownLocation(String day, Category category) =>
    Uri(path: '/statistics/open', queryParameters: {
      'day': day,
      'category': category.json,
    }).toString();

/// The route `/statistics/open?day=&category=`.
GoRoute openStatisticsRoute() => GoRoute(
      path: '/statistics/open',
      builder: (_, s) => OpenDrilldownScreen(
        day: s.uri.queryParameters['day'] ?? dateKey(DateTime.now()),
        category: Category.tryParse(s.uri.queryParameters['category']),
      ),
    );

/// Lists the tasks of one category of a week that are not done yet. A task
/// can be marked done from here.
class OpenDrilldownScreen extends ConsumerStatefulWidget {
  /// Creates the screen. [day] is a `YYYY-MM-DD` key inside the week.
  const OpenDrilldownScreen(
      {required this.day, required this.category, super.key});

  /// A day of the week.
  final String day;

  /// The category, or null when the address named none that is known.
  final Category? category;

  @override
  ConsumerState<OpenDrilldownScreen> createState() =>
      _OpenDrilldownScreenState();
}

class _OpenDrilldownScreenState extends ConsumerState<OpenDrilldownScreen> {
  String? _error;

  Future<void> _complete(OpenTask task) async {
    try {
      await ref.read(planningApiProvider).completeTask(task.id);
    } on DioException catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
      return;
    }
    if (!mounted) return;
    setState(() => _error = null);
    ref.invalidate(openTasksProvider);
    ref.invalidate(statisticsProvider);
    ref.invalidate(taskListProvider);
  }

  @override
  Widget build(BuildContext context) {
    final day = DateTime.tryParse(widget.day);
    final category = widget.category;
    final back =
        '/week?date=${day == null ? dateKey(DateTime.now()) : widget.day}';
    if (day == null || category == null || category == Category.hidden) {
      return AppShell(
        title: 'Tasks still to do',
        backTo: back,
        body: const EmptyState(message: 'This list cannot be opened.'),
      );
    }
    final key = periodDayKey('week', day);
    final async = ref.watch(openTasksProvider(key));
    final text = Theme.of(context).textTheme;
    final quiet = text.bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return AppShell(
      title: 'Tasks still to do',
      backTo: back,
      body: async.when(
        loading: () => const Loading(),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(apiErrorMessage(e), key: const Key('open-drilldown-error')),
              TextButton(
                key: const Key('open-drilldown-retry'),
                onPressed: () => ref.invalidate(openTasksProvider(key)),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
        data: (s) {
          final tasks = s.of(category);
          return ListView(
            padding: const EdgeInsets.all(Space.lg),
            children: [
              Wrap(
                key: const Key('drilldown-title'),
                spacing: Space.md,
                runSpacing: Space.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  CategoryBadge(category: category, count: tasks.length),
                  Text(weekTitle(weekStartOf(day)), style: text.titleMedium),
                ],
              ),
              const SizedBox(height: Space.xs),
              Text(
                'Tasks due or planned this week that are not done yet. This '
                'is a live list: it shows the tasks as of the last sync.',
                key: const Key('live-note'),
                style: quiet,
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: Space.sm),
                  child: Text(_error!,
                      key: const Key('open-work-action-error'),
                      style: text.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error)),
                ),
              const SizedBox(height: Space.md),
              if (tasks.isEmpty)
                Text('Nothing left here.',
                    key: const Key('open-drilldown-empty'), style: quiet)
              else
                for (final t in tasks)
                  OpenTaskRow(task: t, onComplete: () => _complete(t)),
            ],
          );
        },
      ),
    );
  }
}
