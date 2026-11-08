/// A field that opens a picker when tapped (a day or a time).
library;

import 'package:flutter/material.dart';

import '../../theme/theme.dart';

/// A read-only looking field that opens a picker when tapped, with a button
/// that clears it.
class PickerField extends StatelessWidget {
  /// Creates the field. [fieldKey] is on the tappable area, [clearKey] on the clear
  /// button, and `<fieldKey>-value` on the text.
  const PickerField({
    required this.fieldKey,
    required this.clearKey,
    required this.label,
    required this.value,
    required this.empty,
    required this.onTap,
    required this.onClear,
    super.key,
  });

  /// Key of the tappable area.
  final ValueKey<String> fieldKey;

  /// Key of the button that clears the field.
  final Key clearKey;

  /// Label of the field.
  final String label;

  /// The chosen value, or null when there is none.
  final String? value;

  /// Text shown when there is no value.
  final String empty;

  /// Opens the picker; null turns the field off.
  final VoidCallback? onTap;

  /// Clears the value; null hides the clear button.
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return InkWell(
      key: fieldKey,
      borderRadius: BorderRadius.circular(Corner.md),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: onClear == null
              ? null
              : IconButton(
                  key: clearKey,
                  tooltip: 'Clear',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: onClear,
                ),
        ),
        child: Text(value ?? empty,
            key: Key('${fieldKey.value}-value'),
            style:
                text.bodyMedium?.copyWith(color: value == null ? muted : null),
            overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
