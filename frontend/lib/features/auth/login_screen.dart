/// Username/password login screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth_controller.dart';
import '../../theme/theme.dart';

/// Login form.
class LoginScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = ref.watch(authControllerProvider).error;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: TefteriWordmark(size: 44),
                  ),
                  const SizedBox(height: Space.sm),
                  Text('Your plans, on one page.',
                      style: text.titleLarge
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: Space.xxl),
                  TextField(
                      key: const Key('username'),
                      controller: _user,
                      decoration: const InputDecoration(labelText: 'Username')),
                  const SizedBox(height: Space.md),
                  TextField(
                      key: const Key('password'),
                      controller: _pass,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Password'),
                      onSubmitted: (_) => _submit()),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: Space.sm),
                      child: Text(error,
                          style:
                              text.bodyMedium?.copyWith(color: scheme.error)),
                    ),
                  const SizedBox(height: Space.lg),
                  FilledButton(
                      key: const Key('login-button'),
                      onPressed: _submit,
                      child: const Text('Sign in')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _submit() =>
      ref.read(authControllerProvider.notifier).login(_user.text, _pass.text);
}
