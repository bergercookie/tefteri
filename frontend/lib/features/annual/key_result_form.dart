/// The form for a new or changed key result: metric, start value, target,
/// deadline and update source, with the field messages of FR-005.
library;

import 'package:flutter/material.dart';

import '../../core/api_error.dart';
import '../../theme/theme.dart';
import 'annual_models.dart';
import 'annual_term_hint.dart';
import 'theme_picker.dart';

/// Parses a number as the user types it (`12`, `1.5` or `1,5`); null when it
/// is not a finite number.
double? parseNumber(String s) {
  final v = double.tryParse(s.trim().replaceAll(',', '.'));
  return v == null || !v.isFinite ? null : v;
}

/// Parses `YYYY-MM-DD`; null when it is not a valid day.
DateTime? parseDay(String s) {
  final t = s.trim();
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(t)) return null;
  final d = DateTime.tryParse(t);
  return d == null || isoDate(d) != t ? null : d;
}

/// Opens the form. With [existing] it edits that key result (the start value
/// cannot change then); else it makes a new one for [year]. [onSave] stores
/// the draft and throws on failure; the form stays open and shows the
/// message then.
Future<void> showKeyResultForm(
  BuildContext context, {
  required int year,
  required Future<void> Function(KeyResultDraft draft) onSave,
  KeyResult? existing,
  String? initialMetric,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) => KeyResultForm(
          year: year,
          existing: existing,
          initialMetric: initialMetric,
          onSave: onSave),
    );

/// The key result form as a dialog.
class KeyResultForm extends StatefulWidget {
  /// Creates the form.
  const KeyResultForm({
    required this.year,
    required this.onSave,
    this.existing,
    this.initialMetric,
    super.key,
  });

  /// The planning year; the deadline must fall in it.
  final int year;

  /// The key result to change, or null for a new one.
  final KeyResult? existing;

  /// A metric to start with, such as the old criteria text.
  final String? initialMetric;

  /// Stores the draft.
  final Future<void> Function(KeyResultDraft draft) onSave;

  @override
  State<KeyResultForm> createState() => _KeyResultFormState();
}

class _KeyResultFormState extends State<KeyResultForm> {
  late final TextEditingController _metric;
  late final TextEditingController _start;
  late final TextEditingController _target;
  late final TextEditingController _deadline;
  late bool _automatic;
  List<ThemeOption> _themes = const [];
  String? _metricError;
  String? _startError;
  String? _targetError;
  String? _deadlineError;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _metric = TextEditingController(text: e?.metric ?? widget.initialMetric);
    _start = TextEditingController(
        text: e == null ? '' : formatNumber(e.startValue));
    _target =
        TextEditingController(text: e == null ? '' : formatNumber(e.target));
    _deadline =
        TextEditingController(text: e?.deadline ?? '${widget.year}-12-31');
    _automatic = e?.automatic ?? false;
  }

  @override
  void dispose() {
    _metric.dispose();
    _start.dispose();
    _target.dispose();
    _deadline.dispose();
    super.dispose();
  }

  KeyResultDraft? _validate() {
    final metric = _metric.text.trim();
    final start = parseNumber(_start.text);
    final target = parseNumber(_target.text);
    final deadline = parseDay(_deadline.text);
    setState(() {
      _metricError = metric.isEmpty ? 'Write what you measure.' : null;
      _startError = start == null ? 'The start value must be a number.' : null;
      _targetError = target == null
          ? 'The target must be a number.'
          : (start != null && target == start)
              ? 'The target must differ from the start value.'
              : null;
      _deadlineError = deadline == null
          ? 'Write the deadline as YYYY-MM-DD.'
          : deadline.year != widget.year
              ? 'The deadline must fall in ${widget.year}.'
              : null;
    });
    if (_metricError != null ||
        _startError != null ||
        _targetError != null ||
        _deadlineError != null) {
      return null;
    }
    return KeyResultDraft(
      metric: metric,
      startValue: start!,
      target: target!,
      deadline: isoDate(deadline!),
      updateSource: _automatic ? 'automatic' : 'manual',
      themes: _themes,
    );
  }

  Future<void> _save() async {
    final draft = _validate();
    if (draft == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(draft);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = apiErrorMessage(e);
        });
      }
    }
  }

  Future<void> _chooseThemes() async {
    final picked = await pickThemes(context, selected: _themes);
    if (picked != null && mounted) setState(() => _themes = picked);
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      key: const Key('kr-form'),
      title: Text(editing ? 'Change key result' : 'New key result'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AnnualTermHint(AnnualTerm.keyResult),
              TextField(
                key: const Key('kr-metric'),
                controller: _metric,
                autofocus: !editing,
                decoration: InputDecoration(
                  labelText: 'Metric',
                  hintText: 'Stars on the main repository',
                  errorText: _metricError,
                ),
              ),
              const SizedBox(height: Space.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('kr-start'),
                      controller: _start,
                      enabled: !editing,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true, signed: true),
                      decoration: InputDecoration(
                        labelText: 'Start value',
                        errorText: _startError,
                        errorMaxLines: 2,
                        helperText: editing ? 'Cannot change' : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: TextField(
                      key: const Key('kr-target'),
                      controller: _target,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true, signed: true),
                      decoration: InputDecoration(
                          labelText: 'Target',
                          errorText: _targetError,
                          errorMaxLines: 2),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.sm),
              TextField(
                key: const Key('kr-deadline'),
                controller: _deadline,
                decoration: InputDecoration(
                  labelText: 'Deadline (YYYY-MM-DD)',
                  errorText: _deadlineError,
                ),
              ),
              const SizedBox(height: Space.sm),
              const AnnualTermHint(AnnualTerm.automatic),
              SwitchListTile(
                key: const Key('kr-source'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Automatic'),
                subtitle: const Text(
                    'An outside source may send values. You can still enter values by hand.'),
                value: _automatic,
                onChanged: (v) => setState(() => _automatic = v),
              ),
              if (!editing) ...[
                const SizedBox(height: Space.xs),
                Wrap(
                  spacing: Space.xs,
                  runSpacing: Space.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(_themes.isEmpty ? 'No theme linked yet.' : 'Themes:',
                        style: text.bodySmall),
                    for (final t in _themes) Chip(label: Text(t.name)),
                    TextButton.icon(
                      key: const Key('kr-choose-themes'),
                      onPressed: _chooseThemes,
                      icon: const Icon(Icons.link, size: 18),
                      label: const Text('Choose themes'),
                    ),
                  ],
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: Space.sm),
                  child: Text(_error!,
                      key: const Key('kr-error'),
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('kr-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('kr-save'),
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }
}
