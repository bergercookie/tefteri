/// The append-only log of monthly focus changes and its undo actions.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../theme/theme.dart';
import 'month_api.dart';
import 'month_models.dart';

/// Opens the history as a bottom sheet.
Future<void> showFocusHistorySheet(
  BuildContext context, {
  required String month,
  required Future<void> Function(String batchId) onUndo,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FocusHistorySheet(month: month, onUndo: onUndo),
    );

/// History list with a per-change undo action.
class FocusHistorySheet extends ConsumerStatefulWidget {
  /// Creates the sheet.
  const FocusHistorySheet({
    required this.month,
    required this.onUndo,
    super.key,
  });

  /// Month key.
  final String month;

  /// Applies the selected undo.
  final Future<void> Function(String batchId) onUndo;

  @override
  ConsumerState<FocusHistorySheet> createState() => _FocusHistorySheetState();
}

class _FocusHistorySheetState extends ConsumerState<FocusHistorySheet> {
  late Future<List<MonthFocusChange>> _history;
  String? _error;

  @override
  void initState() {
    super.initState();
    _history = ref.read(monthApiProvider).history(widget.month);
  }

  Future<void> _undo(String batchId) async {
    setState(() => _error = null);
    try {
      await widget.onUndo(batchId);
      if (mounted) {
        setState(
            () => _history = ref.read(monthApiProvider).history(widget.month));
      }
    } catch (error) {
      if (mounted) setState(() => _error = apiErrorMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: FutureBuilder<List<MonthFocusChange>>(
            future: _history,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const SizedBox(height: 180, child: Loading());
              }
              if (snapshot.hasError) {
                return SizedBox(
                  height: 180,
                  child: EmptyState(
                    message: apiErrorMessage(snapshot.error!),
                    action: TextButton(
                      onPressed: () => setState(() => _history =
                          ref.read(monthApiProvider).history(widget.month)),
                      child: const Text('Try again'),
                    ),
                  ),
                );
              }
              final items = snapshot.data ?? const [];
              return SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.72,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Focus change history',
                        style: Theme.of(context).textTheme.titleLarge),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: Space.sm),
                        child: Text(_error!, key: const Key('history-error')),
                      ),
                    const SizedBox(height: Space.md),
                    Expanded(
                      child: items.isEmpty
                          ? EmptyState(
                              message: 'No changes yet.',
                              action: TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Back to this month'),
                              ),
                            )
                          : ListView(
                              children: [
                                for (final item in items)
                                  _HistoryRow(
                                    item: item,
                                    onUndo: () => _undo(item.batchId),
                                  ),
                              ],
                            ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.item, required this.onUndo});

  final MonthFocusChange item;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) => Container(
        key: Key('focus-history-${item.batchId}'),
        margin: const EdgeInsets.only(bottom: Space.sm),
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(
          border: Border.all(color: context.tefteri.rule),
          borderRadius: BorderRadius.circular(Corner.md),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${item.on} · ${item.kind}'),
                  if (item.outName != null || item.inName != null)
                    Text('${item.outName ?? '—'} → ${item.inName ?? '—'}'),
                  if (item.undone) const Text('Undone'),
                ],
              ),
            ),
            if (item.canUndo)
              TextButton(
                key: Key('undo-change-${item.batchId}'),
                onPressed: onUndo,
                child: const Text('Undo'),
              ),
          ],
        ),
      );
}
