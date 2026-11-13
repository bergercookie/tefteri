/// The dialog that stores a new value of a key result with its date (FR-009).
/// It is open in every year, also for an automatic key result.
library;

import 'package:flutter/material.dart';

import '../../core/api_error.dart';
import '../../theme/theme.dart';
import 'annual_models.dart';
import 'key_result_form.dart';

/// Opens the dialog for [keyResult]. [onSave] stores the value and throws on
/// failure; the dialog stays open and shows the message then.
Future<void> showValueDialog(
  BuildContext context, {
  required KeyResult keyResult,
  required DateTime today,
  required Future<void> Function(double value, String date) onSave,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) =>
          ValueDialog(keyResult: keyResult, today: today, onSave: onSave),
    );

/// The value dialog.
class ValueDialog extends StatefulWidget {
  /// Creates the dialog.
  const ValueDialog(
      {required this.keyResult,
      required this.today,
      required this.onSave,
      super.key});

  /// The key result.
  final KeyResult keyResult;

  /// Today, the default date.
  final DateTime today;

  /// Stores the value.
  final Future<void> Function(double value, String date) onSave;

  @override
  State<ValueDialog> createState() => _ValueDialogState();
}

class _ValueDialogState extends State<ValueDialog> {
  final _value = TextEditingController();
  late final _date = TextEditingController(text: isoDate(widget.today));
  late int _yesNoValue = widget.keyResult.currentValue >= 0.5 ? 1 : 0;
  String? _valueError;
  String? _dateError;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _value.dispose();
    _date.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = widget.keyResult.yesNo
        ? _yesNoValue.toDouble()
        : parseNumber(_value.text);
    final day = parseDay(_date.text);
    setState(() {
      _valueError = value == null ? 'The value must be a number.' : null;
      _dateError = day == null ? 'Write the date as YYYY-MM-DD.' : null;
    });
    if (value == null || day == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(value, isoDate(day));
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

  @override
  Widget build(BuildContext context) {
    final kr = widget.keyResult;
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      key: const Key('value-dialog'),
      title: const Text('Update value'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(kr.metric, style: text.titleSmall),
            Text(
                kr.yesNo
                    ? 'Now ${kr.yesNoAnswer} · deadline ${kr.deadline}'
                    : 'Now ${formatNumber(kr.currentValue)} · start '
                        '${formatNumber(kr.startValue)} · target ${formatNumber(kr.target)}',
                style: text.bodySmall),
            if (kr.automatic)
              Padding(
                padding: const EdgeInsets.only(top: Space.sm),
                child: Text(
                  'This key result is automatic. A value you enter here is '
                  'kept as a manual value.',
                  key: const Key('value-auto-note'),
                  style: text.bodySmall,
                ),
              ),
            const SizedBox(height: Space.sm),
            if (kr.yesNo)
              SegmentedButton<int>(
                key: const Key('value-yes-no'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 0, label: Text('No')),
                  ButtonSegment(value: 1, label: Text('Yes')),
                ],
                selected: {_yesNoValue},
                onSelectionChanged: (s) =>
                    setState(() => _yesNoValue = s.first),
              )
            else
              TextField(
                key: const Key('value-field'),
                controller: _value,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
                decoration: InputDecoration(
                    labelText: 'New value', errorText: _valueError),
                onSubmitted: (_) => _save(),
              ),
            const SizedBox(height: Space.sm),
            TextField(
              key: const Key('value-date'),
              controller: _date,
              decoration: InputDecoration(
                  labelText: 'Date (YYYY-MM-DD)',
                  helperText: 'The latest date is the current value.',
                  errorText: _dateError),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: Space.sm),
                child: Text(_error!,
                    key: const Key('value-error'),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('value-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('value-save'),
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save value'),
        ),
      ],
    );
  }
}
