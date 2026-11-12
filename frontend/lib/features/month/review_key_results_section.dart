/// Key-result values and the milestone/key-result gap in a monthly review.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/theme.dart';

/// Shows latest series values, optional manual entries, and theme gaps.
class ReviewKeyResultsSection extends StatelessWidget {
  /// Creates the section.
  const ReviewKeyResultsSection({
    required this.snapshot,
    required this.values,
    required this.onValueChanged,
    super.key,
  });

  /// Snapshot or draft payload.
  final Map<String, dynamic> snapshot;

  /// Unsaved values typed into this month.
  final Map<String, num> values;

  /// Keeps an unsaved value in the month-specific review draft.
  final void Function(String keyResultId, num? value) onValueChanged;

  @override
  Widget build(BuildContext context) {
    final themes = snapshot['themes'] as List? ?? const [];
    final keyResults = snapshot['key_results'] as List? ?? const [];
    if (keyResults.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Key results and milestones',
              style: Theme.of(context).textTheme.titleLarge),
          const EmptyState(
            message: 'No key results are linked to this month.',
            icon: Icons.insights_outlined,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => context.go('/annual'),
              child: const Text('Open annual planning'),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Key results and milestones',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: Space.xs),
        Text(
          'Milestones shipped and key-result movement are shown side by side. '
          'This does not say one caused the other.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        for (final rawTheme in themes)
          if (rawTheme is Map)
            _ThemeGap(
              theme: Map<String, dynamic>.from(rawTheme),
              keyResults: keyResults
                  .whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .toList(),
              values: values,
              onValueChanged: onValueChanged,
            ),
      ],
    );
  }
}

class _ThemeGap extends StatelessWidget {
  const _ThemeGap({
    required this.theme,
    required this.keyResults,
    required this.values,
    required this.onValueChanged,
  });

  final Map<String, dynamic> theme;
  final List<Map<String, dynamic>> keyResults;
  final Map<String, num> values;
  final void Function(String, num?) onValueChanged;

  @override
  Widget build(BuildContext context) {
    final id = '${theme['project_id']}';
    final linked = keyResults
        .where((result) => (result['theme_ids'] as List? ?? const [])
            .map((themeId) => '$themeId')
            .contains(id))
        .toList();
    return Container(
      key: Key('key-result-gap-$id'),
      margin: const EdgeInsets.only(top: Space.md),
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        border: Border.all(color: context.tefteri.rule),
        borderRadius: BorderRadius.circular(Corner.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
              '${theme['name'] ?? ''} · ${theme['done'] ?? 0} milestones shipped',
              style: Theme.of(context).textTheme.titleSmall),
          if (linked.isEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => context.go('/annual'),
                child:
                    const Text('No linked key result · Open annual planning'),
              ),
            ),
          for (final result in linked)
            _KeyResultGapRow(
              result: result,
              typedValue: values['${result['key_result_id']}'],
              onValueChanged: onValueChanged,
            ),
        ],
      ),
    );
  }
}

class _KeyResultGapRow extends StatefulWidget {
  const _KeyResultGapRow({
    required this.result,
    required this.typedValue,
    required this.onValueChanged,
  });

  final Map<String, dynamic> result;
  final num? typedValue;
  final void Function(String, num?) onValueChanged;

  @override
  State<_KeyResultGapRow> createState() => _KeyResultGapRowState();
}

class _KeyResultGapRowState extends State<_KeyResultGapRow> {
  late final TextEditingController _value;
  String? _error;

  @override
  void initState() {
    super.initState();
    _value = TextEditingController(text: widget.typedValue?.toString() ?? '');
  }

  @override
  void didUpdateWidget(covariant _KeyResultGapRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.typedValue != widget.typedValue &&
        widget.typedValue != null) {
      _value.text = widget.typedValue.toString();
    }
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  void _edit(String text) {
    if (text.trim().isEmpty) {
      setState(() => _error = null);
      widget.onValueChanged('${widget.result['key_result_id']}', null);
      return;
    }
    final number = num.tryParse(text.trim());
    if (number == null || !number.isFinite) {
      setState(() => _error = 'Enter a finite number, or leave it empty.');
      return;
    }
    setState(() => _error = null);
    widget.onValueChanged('${widget.result['key_result_id']}', number);
  }

  @override
  Widget build(BuildContext context) {
    final id = '${widget.result['key_result_id']}';
    final base = _number(widget.result['base_value']);
    final latest = widget.typedValue ?? _number(widget.result['latest_value']);
    final change = widget.typedValue == null
        ? _number(widget.result['change'])
        : latest - base;
    final shared = widget.result['shared'] == true;
    final notUpdated = widget.result['status'] == 'not_updated';
    final manual = widget.result['update_source'] == 'manual' &&
        widget.result['retired'] != true;
    final at = widget.result['latest_at'];
    return Container(
      key: Key('review-key-result-$id'),
      margin: const EdgeInsets.only(top: Space.sm),
      padding: const EdgeInsets.only(top: Space.sm),
      decoration: BoxDecoration(
          border: Border(top: BorderSide(color: context.tefteri.rule))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${widget.result['goal_title'] ?? ''} · '
              '${widget.result['metric'] ?? ''}'),
          Text(
            'Base $base · Latest $latest · Change ${_signed(change)}',
            key: Key('key-result-gap-values-$id'),
          ),
          if (at != null)
            Text('Latest value: $at',
                key: Key('key-result-timestamp-$id'),
                style: Theme.of(context).textTheme.bodySmall),
          if (notUpdated)
            Text('Not updated this month',
                key: Key('not-updated-$id'),
                style: Theme.of(context).textTheme.bodySmall),
          if (widget.result['past_deadline'] == true)
            const Text('Past deadline'),
          if (shared)
            Text('Shared by more than one theme.',
                key: Key('shared-key-result-$id'),
                style: Theme.of(context).textTheme.bodySmall),
          if (manual) ...[
            const SizedBox(height: Space.xs),
            TextField(
              key: Key('manual-value-$id'),
              controller: _value,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'New value (optional)',
                helperText: 'You can skip this update.',
                errorText: _error,
              ),
              onChanged: _edit,
            ),
            TextButton(
              key: Key('skip-value-$id'),
              onPressed: () {
                _value.clear();
                _edit('');
              },
              child: const Text('Skip this value'),
            ),
          ],
        ],
      ),
    );
  }

  num _number(Object? value) => value is num ? value : 0;

  String _signed(num value) => value > 0 ? '+$value' : '$value';
}
