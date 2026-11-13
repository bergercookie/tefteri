/// The live drill-down of the year split (feature 005 owns the list).
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/theme.dart';
import '../statistics/drilldown_screen.dart';
import '../statistics/statistics_models.dart' as stats;

/// Opens the live tasks of one category for a year.
void openYearDrillDown(
        BuildContext context, int year, stats.Category? category) =>
    openDrilldown(context, 'year', '$year-01-01', category);

/// The route of the live list for a year, for a button that must not push.
String yearDrillDownLocation(int year, stats.Category? category) =>
    drilldownLocation('year', '$year-01-01', category);

/// A small sheet that explains that the list is live and opens it.
Future<void> showDrillDownSheet(
    BuildContext context, int year, stats.Category? category) async {
  await showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Live list, may differ from the bar.',
                key: Key('drill-down-live')),
            const SizedBox(height: Space.md),
            FilledButton(
              key: const Key('drill-down-go'),
              onPressed: () {
                Navigator.of(context).pop();
                GoRouter.maybeOf(context)
                    ?.push(yearDrillDownLocation(year, category));
              },
              child: const Text('Open the live list'),
            ),
          ],
        ),
      ),
    ),
  );
}
