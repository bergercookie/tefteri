/// Username/password login screen.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth_controller.dart';
import '../../core/server_address.dart';
import '../../core/versions.dart';
import 'credential_form.dart';
import '../../theme/theme.dart';

/// Login form.
class LoginScreen extends ConsumerStatefulWidget {
  /// Creates the screen. The server field shows when [showServer] is true;
  /// by default that is every client except the browser one.
  const LoginScreen(
      {bool? showServer, CredentialFormBuilder? credentialForm, super.key})
      : _showServer = showServer,
        _credentialForm = credentialForm ?? webCredentialForm;

  final bool? _showServer;

  /// Builds the login form as HTML (the web one by default). Tests replace it.
  final CredentialFormBuilder _credentialForm;

  bool get _askServer => _showServer ?? needsServerAddress;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  late final TextEditingController _server;
  final _user = TextEditingController();
  final _pass = TextEditingController();
  String? _serverError;
  Timer? _typing;
  // The address whose version is shown; it follows the server field.
  String? _probe;

  @override
  void initState() {
    super.initState();
    _server =
        TextEditingController(text: ref.read(serverAddressProvider) ?? '');
    _probe = normalizeServerAddress(_server.text);
  }

  @override
  void dispose() {
    _typing?.cancel();
    _server.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _serverError ?? ref.watch(authControllerProvider).error;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              // AutofillGroup lets password managers (Bitwarden etc.) fill
              // and save the username/password pair as one credential.
              child: AutofillGroup(
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
                    if (widget._askServer) ...[
                      TextField(
                          key: const Key('server'),
                          controller: _server,
                          keyboardType: TextInputType.url,
                          onChanged: _serverEdited,
                          autocorrect: false,
                          decoration: const InputDecoration(
                              labelText: 'Server',
                              hintText: 'https://tefteri.example.com')),
                      const SizedBox(height: Space.md),
                    ],
                    ..._credentialFields(),
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
                    _versionLine(text, scheme),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Username and password. On the web these are real HTML inputs in a form,
  /// so that password managers find them; elsewhere they are Flutter fields
  /// with autofill hints.
  List<Widget> _credentialFields() {
    final web = widget._credentialForm(
      context,
      onUser: (v) => _user.text = v,
      onPass: (v) => _pass.text = v,
      onSubmit: _submit,
    );
    if (web != null) {
      return [KeyedSubtree(key: const Key('web-credentials'), child: web)];
    }
    return [
      TextField(
          key: const Key('username'),
          controller: _user,
          autofillHints: const [AutofillHints.username],
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(labelText: 'Username')),
      const SizedBox(height: Space.md),
      TextField(
          key: const Key('password'),
          controller: _pass,
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(labelText: 'Password'),
          onSubmitted: (_) => _submit()),
    ];
  }

  /// Looks up the server's version a moment after the user stops typing.
  void _serverEdited(String value) {
    _typing?.cancel();
    _typing = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _probe = normalizeServerAddress(value));
    });
  }

  /// "Server version 1.2.3", or why it is not known. The web client asks the
  /// server it was loaded from; the others ask the address in the field.
  Widget _versionLine(TextTheme text, ColorScheme scheme) {
    final asks = kIsWeb || (widget._askServer && _probe != null);
    if (!asks) return const SizedBox.shrink();
    final version = ref.watch(serverVersionProvider(kIsWeb ? null : _probe));
    final style = text.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.only(top: Space.md),
      child: Text(
        version.when(
          data: (v) => 'Server version $v',
          loading: () => 'Checking the server...',
          error: (_, __) => 'Server version unknown (cannot reach it)',
        ),
        key: const Key('server-version'),
        style: style,
        textAlign: TextAlign.center,
      ),
    );
  }

  Future<void> _submit() async {
    if (widget._askServer) {
      final address = normalizeServerAddress(_server.text);
      if (address == null) {
        setState(() => _serverError = 'Enter the address of your server');
        return;
      }
      setState(() => _serverError = null);
      _server.text = address;
      await ref.read(serverAddressProvider.notifier).set(address);
    }
    await ref
        .read(authControllerProvider.notifier)
        .login(_user.text, _pass.text);
    // Tells the platform the login succeeded so it can offer to save the
    // credentials; with a failed login the context is cancelled instead.
    // The screen is usually gone by now when login succeeded.
    final failed = mounted && ref.read(authControllerProvider).error != null;
    TextInput.finishAutofillContext(shouldSave: !failed);
  }
}
