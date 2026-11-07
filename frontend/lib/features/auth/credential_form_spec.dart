/// What the web login form must look like to a password manager. The web
/// implementation uses these values; a test pins them.
library;

import 'package:flutter/widgets.dart';

/// `autocomplete` of the username input, as the browser spec names it.
const String usernameAutocomplete = 'username';

/// `autocomplete` of the password input of a login form.
const String passwordAutocomplete = 'current-password';

/// Builds the real HTML form of the web login, or returns null where there is
/// none (every platform but the web).
typedef CredentialFormBuilder = Widget? Function(
  BuildContext context, {
  required ValueChanged<String> onUser,
  required ValueChanged<String> onPass,
  required VoidCallback onSubmit,
});
