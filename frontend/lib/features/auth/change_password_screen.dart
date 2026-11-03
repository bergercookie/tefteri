/// Screen where a signed-in user changes their own password.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/api_error.dart';
import '../../core/shell.dart';

/// Form with the current and the new password.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _done = false;
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_next.text != _confirm.text) {
      setState(() {
        _done = false;
        _error = 'The new passwords do not match.';
      });
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(dioProvider).post<void>('/auth/password', data: {
        'current_password': _current.text,
        'new_password': _next.text,
      });
      if (!mounted) return;
      _current.clear();
      _next.clear();
      _confirm.clear();
      setState(() {
        _error = null;
        _done = true;
      });
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _done = false;
          _error = apiErrorMessage(e);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Change password',
      backTo: '/settings',
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            if (_error != null)
              ErrorBanner(
                message: _error!,
                onDismiss: () => setState(() => _error = null),
              ),
            if (_done)
              const Padding(
                key: Key('password-changed'),
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Your password is changed.'),
              ),
            TextField(
              key: const Key('current-password'),
              controller: _current,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Current password'),
            ),
            TextField(
              key: const Key('new-password'),
              controller: _next,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'New password',
                  helperText: 'Use 8 or more characters.'),
            ),
            TextField(
              key: const Key('confirm-password'),
              controller: _confirm,
              obscureText: true,
              decoration:
                  const InputDecoration(labelText: 'Repeat new password'),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('password-save'),
              onPressed: _busy ? null : _submit,
              child: const Text('Change password'),
            ),
          ]),
        ),
      ),
    );
  }
}
