import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../../theme/theme.dart';
import 'credential_form_spec.dart';

/// Height of the two inputs and the gap between them, in CSS pixels.
const double _inputHeight = 52;
const double _formHeight = _inputHeight * 2 + Space.md;

String _css(Color c) =>
    'rgba(${(c.r * 255).round()},${(c.g * 255).round()},${(c.b * 255).round()},${c.a})';

/// A `<form>` with a username and a password input that is in the page from
/// the start, visible and of real size. [onUser] and [onPass] get the text as
/// it changes (typed or filled by a password manager); [onSubmit] runs on
/// Enter.
Widget? webCredentialForm(
  BuildContext context, {
  required ValueChanged<String> onUser,
  required ValueChanged<String> onPass,
  required VoidCallback onSubmit,
}) {
  final scheme = Theme.of(context).colorScheme;
  final font = Theme.of(context).textTheme.bodyLarge?.fontFamily;
  return SizedBox(
    height: _formHeight,
    child: HtmlElementView.fromTagName(
      // A new form when the colours change (light or dark).
      key: ValueKey(scheme.brightness),
      tagName: 'form',
      onElementCreated: (Object element) {
        final form = element as web.HTMLFormElement;
        form
          ..id = 'tefteri-login'
          ..noValidate = true;
        form.style
          ..display = 'flex'
          ..flexDirection = 'column'
          ..setProperty('gap', '${Space.md}px')
          ..width = '100%'
          ..height = '100%';

        web.HTMLInputElement input(String type, String name,
            String autocomplete, String label, ValueChanged<String> changed) {
          final el = web.document.createElement('input') as web.HTMLInputElement
            ..type = type
            ..name = name
            ..id = name
            ..placeholder = label
            ..autocomplete = autocomplete;
          el.setAttribute('aria-label', label);
          el.style
            ..boxSizing = 'border-box'
            ..width = '100%'
            ..height = '${_inputHeight}px'
            ..padding = '0 ${Space.md}px'
            ..fontSize = '16px'
            ..fontFamily = font ?? 'sans-serif'
            ..color = _css(scheme.onSurface)
            ..backgroundColor = _css(scheme.surface)
            ..border = '1px solid ${_css(scheme.outline)}'
            ..borderRadius = '${Corner.md}px'
            ..outline = 'none';
          el.addEventListener(
              'focus',
              ((web.Event _) => el.style.borderColor = _css(scheme.primary))
                  .toJS);
          el.addEventListener(
              'blur',
              ((web.Event _) => el.style.borderColor = _css(scheme.outline))
                  .toJS);
          // A password manager sets the value and fires input and change.
          el.addEventListener(
              'input', ((web.Event _) => changed(el.value)).toJS);
          el.addEventListener(
              'change', ((web.Event _) => changed(el.value)).toJS);
          return el;
        }

        form
          ..append(input(
              'text', 'username', usernameAutocomplete, 'Username', onUser))
          ..append(input('password', 'current-password', passwordAutocomplete,
              'Password', onPass));
        // Enter submits; the page itself never reloads.
        form.addEventListener(
            'submit',
            ((web.Event e) {
              e.preventDefault();
              onSubmit();
            }).toJS);
        // A form needs a submit control for Enter to work in every browser.
        final submit =
            web.document.createElement('input') as web.HTMLInputElement
              ..type = 'submit'
              ..tabIndex = -1;
        submit.style
          ..position = 'absolute'
          ..width = '1px'
          ..height = '1px'
          ..opacity = '0'
          ..setProperty('pointer-events', 'none');
        form.append(submit);
      },
    ),
  );
}
