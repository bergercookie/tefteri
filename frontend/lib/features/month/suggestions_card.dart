/// Editable, unsaved themes carried forward from the latest stored review.
library;

import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import 'month_models.dart';
import 'target_field.dart';

/// Lets the user keep or remove last month's focus suggestions.
class SuggestionsCard extends StatefulWidget {
  /// Creates the suggestions card.
  const SuggestionsCard({
    required this.suggestions,
    required this.onChanged,
    this.showItems = true,
    this.onValidityChanged,
    super.key,
  });

  /// Suggestions returned by the monthly API.
  final MonthSuggestions suggestions;

  /// Receives the editable selection; it is not saved until plan Save.
  final ValueChanged<List<MonthSuggestion>> onChanged;

  /// Whether to list themes; the month screen shows them in its focus section.
  final bool showItems;

  /// Reports whether every visible target remains valid.
  final ValueChanged<bool>? onValidityChanged;

  @override
  State<SuggestionsCard> createState() => _SuggestionsCardState();
}

class _SuggestionsCardState extends State<SuggestionsCard> {
  late List<MonthSuggestion> _selected;
  final Set<String> _invalidTargets = {};

  @override
  void initState() {
    super.initState();
    _selected = List.of(widget.suggestions.suggestions);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onChanged(List.of(_selected));
    });
  }

  void _remove(MonthSuggestion suggestion) {
    setState(() {
      _selected.removeWhere((item) => item.projectId == suggestion.projectId);
      _invalidTargets.remove(suggestion.projectId);
    });
    widget.onValidityChanged?.call(_invalidTargets.isEmpty);
    widget.onChanged(List.of(_selected));
  }

  void _setTarget(MonthSuggestion suggestion, int? target) {
    setState(() {
      final index = _selected
          .indexWhere((item) => item.projectId == suggestion.projectId);
      if (index >= 0) {
        _selected[index] = MonthSuggestion.fromJson({
          'project_id': suggestion.projectId,
          'name': suggestion.name,
          'target': target,
          'reason': suggestion.reason,
          'replaces': suggestion.replaces,
        });
      }
    });
    widget.onChanged(List.of(_selected));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.suggestions.fromMonth == null ||
        widget.suggestions.suggestions.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      key: const Key('suggestions-card'),
      margin: const EdgeInsets.only(bottom: Space.lg),
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        border: Border.all(color: context.tefteri.rule),
        borderRadius: BorderRadius.circular(Corner.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Suggestions from ${widget.suggestions.fromMonth}',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Space.xs),
          Text('These are editable. They are not saved until you choose Save.',
              style: Theme.of(context).textTheme.bodySmall),
          if (widget.showItems)
            for (final suggestion in _selected)
              Padding(
                padding: const EdgeInsets.only(top: Space.md),
                child: Row(
                  children: [
                    Expanded(child: Text(suggestion.name)),
                    SizedBox(
                      width: 150,
                      child: TargetField(
                        key: Key('suggestion-target-${suggestion.projectId}'),
                        initialValue: suggestion.target,
                        onChanged: (target) => _setTarget(suggestion, target),
                        onValidityChanged: (valid) {
                          setState(() {
                            if (valid) {
                              _invalidTargets.remove(suggestion.projectId);
                            } else {
                              _invalidTargets.add(suggestion.projectId);
                            }
                          });
                          widget.onValidityChanged
                              ?.call(_invalidTargets.isEmpty);
                        },
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove suggestion',
                      key: Key('remove-suggestion-${suggestion.projectId}'),
                      onPressed: () => _remove(suggestion),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
          if (widget.showItems && _selected.isEmpty)
            Text('No suggestions selected.',
                style: Theme.of(context).textTheme.bodySmall),
          if (widget.suggestions.skipped.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Space.md),
              child: Text(
                'Some themes from ${widget.suggestions.fromMonth} were skipped '
                'because they are no longer available.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}
