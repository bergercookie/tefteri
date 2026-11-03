/// Dialog that adds a connection or edits one.
library;

import 'package:flutter/material.dart';

import 'connection_models.dart';

/// An app that tefteri can connect to.
enum ConnectionProvider {
  /// Vikunja tasks, with a base URL and an API token.
  vikunja('vikunja', 'Vikunja', 'API token'),

  /// Google Calendar, through the Google sign-in page.
  googleCalendar('google_calendar', 'Google Calendar', null),

  /// Trilium Next notes, with a base URL and an ETAPI token.
  trilium('trilium', 'Trilium Next', 'ETAPI token');

  const ConnectionProvider(this.id, this.label, this.tokenLabel);

  /// Provider name in the API.
  final String id;

  /// Name shown to the user.
  final String label;

  /// Label of the token field; null when the app uses a sign-in page.
  final String? tokenLabel;

  /// Whether the user types a base URL and a token.
  bool get usesToken => tokenLabel != null;

  /// The provider with API name [id], or null.
  static ConnectionProvider? byId(String id) =>
      values.where((p) => p.id == id).firstOrNull;
}

/// Adds a connection, or edits [initial] when it is given.
///
/// Adding pops the body for `POST /connections` (for Google Calendar, the
/// query of `GET /connections/google/authorize`). Editing pops the body for
/// `PATCH /connections/{id}`: an empty token keeps the stored one. Pops null
/// on cancel.
class ConnectionDialog extends StatefulWidget {
  /// Creates the dialog.
  const ConnectionDialog({this.initial, super.key});

  /// The connection to edit; null to add one.
  final Connection? initial;

  @override
  State<ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends State<ConnectionDialog> {
  late ConnectionProvider _provider =
      ConnectionProvider.byId(widget.initial?.provider ?? '') ??
          ConnectionProvider.vikunja;
  late Set<String> _contexts = switch (widget.initial?.defaultContext) {
    'both' => {'life', 'work'},
    'work' => {'work'},
    _ => {'life'},
  };
  late final _name = TextEditingController(
      text: widget.initial?.displayName ?? _provider.label);
  late final _url = TextEditingController(
      text: '${widget.initial?.settings['base_url'] ?? ''}');
  final _token = TextEditingController();

  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    for (final c in [_name, _url, _token]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  void _choose(ConnectionProvider p) {
    // Keep a name the user typed; replace the default name of the old app.
    if (_name.text.trim().isEmpty || _name.text == _provider.label) {
      _name.text = p.label;
    }
    setState(() => _provider = p);
  }

  bool get _complete =>
      _name.text.trim().isNotEmpty &&
      (!_provider.usesToken ||
          (_url.text.trim().isNotEmpty &&
              (_editing || _token.text.trim().isNotEmpty)));

  void _save() {
    final token = _token.text.trim();
    Navigator.of(context).pop(<String, Object?>{
      if (!_editing) 'provider': _provider.id,
      'display_name': _name.text.trim(),
      'default_context': _contexts.length == 2 ? 'both' : _contexts.single,
      if (_provider.usesToken) ...{
        // Keep other settings, for example Trilium's root note.
        'settings': {
          ...?widget.initial?.settings,
          'base_url': _url.text.trim(),
        },
        if (token.isNotEmpty) 'credentials': {'token': token},
      },
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_editing ? 'Edit connection' : 'Add connection'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<ConnectionProvider>(
                key: const Key('new-connection-provider'),
                initialValue: _provider,
                decoration: const InputDecoration(labelText: 'App'),
                items: [
                  for (final p in ConnectionProvider.values)
                    DropdownMenuItem(value: p, child: Text(p.label)),
                ],
                // The app of an existing connection cannot change.
                onChanged: _editing ? null : (p) => _choose(p ?? _provider),
              ),
              TextField(
                key: const Key('new-connection-name'),
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              if (_provider.usesToken) ...[
                TextField(
                  key: const Key('new-connection-url'),
                  controller: _url,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                      labelText: 'Base URL', hintText: 'https://example.com'),
                ),
                TextField(
                  key: const Key('new-connection-token'),
                  controller: _token,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: _provider.tokenLabel,
                    helperText: _editing
                        ? 'Leave empty to keep the current token.'
                        : null,
                  ),
                ),
              ] else if (!_editing)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text('You sign in on the Google page. Tefteri never '
                      'sees your Google password.'),
                ),
              const SizedBox(height: 12),
              // Projects, calendars and notes without their own label show
              // in the chosen contexts; select both to show them in each.
              const Text('Show unlabelled items in'),
              const SizedBox(height: 4),
              SegmentedButton<String>(
                key: const Key('new-connection-context'),
                multiSelectionEnabled: true,
                segments: const [
                  ButtonSegment(value: 'life', label: Text('Life')),
                  ButtonSegment(value: 'work', label: Text('Work')),
                ],
                selected: _contexts,
                onSelectionChanged: (s) => setState(() => _contexts = s),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('new-connection-save'),
          onPressed: _complete ? _save : null,
          child: Text(_provider.usesToken || _editing ? 'Save' : 'Continue'),
        ),
      ],
    );
  }
}
