/// Helpers that turn API failures into clear messages.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

/// Returns the server's `detail` text for [error], or a plain fallback.
///
/// Write actions can fail with `backend_unavailable`, `auth_expired`,
/// `not_supported` or `remote_conflict`; the detail names the cause.
String apiErrorMessage(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map) {
      final detail = data['detail'];
      // The classification routes answer {"detail": {"code", "message"}}.
      if (detail is Map && detail['message'] != null) {
        return '${detail['message']}';
      }
      if (detail != null && detail is! Map) return '$detail';
    }
    return 'Cannot reach the server.';
  }
  return 'Something went wrong.';
}

/// The machine code of an API error (for example `not_supported`), or null.
String? apiErrorCode(Object error) {
  if (error is! DioException) return null;
  final data = error.response?.data;
  if (data is! Map) return null;
  final detail = data['detail'];
  if (detail is Map && detail['code'] != null) return '${detail['code']}';
  return data['code'] == null ? null : '${data['code']}';
}

/// Banner that shows a failed action. The change is not queued.
class ErrorBanner extends StatelessWidget {
  /// Creates a banner with [message].
  const ErrorBanner({required this.message, this.onDismiss, super.key});

  /// Text to show.
  final String message;

  /// Called when the user closes the banner.
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const Key('error-banner'),
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: scheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message,
                  style: TextStyle(color: scheme.onErrorContainer)),
            ),
            if (onDismiss != null)
              IconButton(
                key: const Key('error-dismiss'),
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                onPressed: onDismiss,
              ),
          ],
        ),
      ),
    );
  }
}
