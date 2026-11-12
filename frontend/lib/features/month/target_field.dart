/// An editable whole-number milestone target (blank means no target).
library;

import 'package:flutter/material.dart';

/// Target field shared by monthly planning and its change dialog.
class TargetField extends StatefulWidget {
  /// Creates a field. Empty text represents no target; zero is retained.
  const TargetField({
    required this.initialValue,
    required this.onChanged,
    this.onValidityChanged,
    this.enabled = true,
    super.key,
  });

  /// Initial target, or null for no target.
  final int? initialValue;

  /// Called with a valid integer or null for an empty field.
  final ValueChanged<int?> onChanged;

  /// Reports whether the current visible text is valid.
  final ValueChanged<bool>? onValidityChanged;

  /// Whether this target can be edited.
  final bool enabled;

  @override
  State<TargetField> createState() => _TargetFieldState();
}

class _TargetFieldState extends State<TargetField> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller =
        TextEditingController(text: widget.initialValue?.toString() ?? '');
  }

  @override
  void didUpdateWidget(covariant TargetField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      _controller.text = widget.initialValue?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _edit(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() => _error = null);
      widget.onValidityChanged?.call(true);
      widget.onChanged(null);
      return;
    }
    final parsed = int.tryParse(trimmed);
    if (parsed == null || parsed < 0) {
      setState(() => _error =
          'Use a whole number of milestones, 0 or more, or leave it empty.');
      widget.onValidityChanged?.call(false);
      return;
    }
    setState(() => _error = null);
    widget.onValidityChanged?.call(true);
    widget.onChanged(parsed);
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _controller,
        enabled: widget.enabled,
        keyboardType:
            const TextInputType.numberWithOptions(signed: true, decimal: true),
        decoration: InputDecoration(
          labelText: 'Milestone target',
          hintText: 'No target',
          helperText: _error == null ? 'Milestones, not hours or time.' : null,
          errorText: _error,
          isDense: true,
        ),
        onChanged: _edit,
      );
}
