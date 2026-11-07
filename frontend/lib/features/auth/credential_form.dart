/// The login fields as a real HTML form, on the web.
///
/// Password managers such as Bitwarden look for `<input autocomplete="username">`
/// and `<input autocomplete="current-password">` in the page. Flutter's own text
/// fields only create such inputs while one has focus, and the one that is not
/// focused is parked off screen at size 0, so a password manager finds no login
/// form. On the web the login screen therefore shows this form instead. On every
/// other platform [webCredentialForm] returns null and the screen keeps its
/// Flutter fields (whose `autofillHints` the Android autofill service reads).
library;

export 'credential_form_spec.dart';
export 'credential_form_stub.dart'
    if (dart.library.js_interop) 'credential_form_web.dart';
