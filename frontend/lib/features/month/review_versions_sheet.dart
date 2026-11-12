/// Version history for immutable monthly review snapshots.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../theme/theme.dart';
import 'month_api.dart';
import 'month_controller.dart';
import 'month_models.dart';

/// Opens the versions list for one stored review.
Future<void> showReviewVersionsSheet(
  BuildContext context, {
  required String month,
  required MonthReview review,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ReviewVersionsSheet(month: month, review: review),
    );

/// Available review snapshots, their dates and the current version.
class ReviewVersionsSheet extends ConsumerStatefulWidget {
  /// Creates the versions sheet.
  const ReviewVersionsSheet({
    required this.month,
    required this.review,
    super.key,
  });

  /// Month key.
  final String month;

  /// Review read model.
  final MonthReview review;

  @override
  ConsumerState<ReviewVersionsSheet> createState() =>
      _ReviewVersionsSheetState();
}

class _ReviewVersionsSheetState extends ConsumerState<ReviewVersionsSheet> {
  String? _error;
  bool _working = false;

  Future<void> _makeCurrent(int version) async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final api = ref.read(monthApiProvider);
      final preview =
          await api.makeCurrent(widget.month, version, dryRun: true);
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Make this version current?'),
          content: Text('${preview['message'] ?? ''}'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Make current')),
          ],
        ),
      );
      if (confirmed != true) return;
      await ref
          .read(monthReviewProvider(widget.month).notifier)
          .makeCurrent(version);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = apiErrorMessage(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Review versions',
                    style: Theme.of(context).textTheme.titleLarge),
                if (_error != null)
                  Text(_error!, key: const Key('versions-error')),
                const SizedBox(height: Space.md),
                Expanded(
                  child: widget.review.versions.isEmpty
                      ? EmptyState(
                          message: 'No saved versions are available.',
                          action: TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Return to review'),
                          ),
                        )
                      : ListView(
                          children: [
                            for (final version in widget.review.versions)
                              if (version['version'] is num)
                                _VersionRow(
                                  version: Map<String, dynamic>.from(version),
                                  working: _working,
                                  onMakeCurrent: () => _makeCurrent(
                                      (version['version'] as num).toInt()),
                                ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({
    required this.version,
    required this.working,
    required this.onMakeCurrent,
  });

  final Map<String, dynamic> version;
  final bool working;
  final VoidCallback onMakeCurrent;

  @override
  Widget build(BuildContext context) {
    final number = (version['version'] as num).toInt();
    final current = version['current'] == true;
    return Container(
      key: Key('review-version-$number'),
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.tefteri.rule))),
      child: Row(
        children: [
          Expanded(
            child: Text('Version $number · ${version['taken_at'] ?? ''}'
                '${current ? ' · Current' : ''}'),
          ),
          if (!current)
            TextButton(
              key: Key('make-current-$number'),
              onPressed: working ? null : onMakeCurrent,
              child: const Text('Make current'),
            ),
        ],
      ),
    );
  }
}
