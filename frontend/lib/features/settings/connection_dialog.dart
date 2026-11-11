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

/// What each required capability of a task app means, in plain words.
const capabilityWords = <String, String>{
  'subprojects': 'Nested projects (projects inside projects, at least two '
      'levels)',
  'project_tree': 'Reading the whole project tree, and noticing projects that '
      'were moved or deleted',
  'stable_project_ids': 'A stable identity for each project, so labels stay '
      'on the right project after a rename',
  'archive_projects': 'Creating and archiving projects',
  'create_tasks': 'Creating tasks',
  'completion_times': 'The time each task was completed',
};

/// The capability names in [text] (an API message or list), in a stable order.
List<String> capabilitiesNamedIn(Object? text) {
  final t = '$text'.toLowerCase().replaceAll(' ', '_');
  return [
    for (final k in capabilityWords.keys)
      if (t.contains(k)) k,
  ];
}

/// The missing capabilities of a connection result: from the list
/// `capabilities.missing_required` of [data], or named in its message.
List<String> missingCapabilitiesOf(Object? data) {
  if (data is! Map) return const [];
  final caps = data['capabilities'];
  if (caps is Map && caps['missing_required'] is List) {
    final names = (caps['missing_required'] as List).map((e) => '$e').toList();
    if (names.isNotEmpty) return names;
  }
  final detail = data['detail'];
  return capabilitiesNamedIn(detail is Map ? detail['message'] : detail);
}

/// Optional capabilities of a task app and what the user loses without them.
const optionalCapabilityNotes = <String, String>{
  'move_tasks': 'Your task app cannot move tasks between projects, so the '
      'weekly review will not offer "Close and return tasks". Everything else '
      'works.',
};

/// Plain sentences about the optional capabilities that [data] (the answer of
/// a connection check) reports as missing, in a stable order.
List<String> missingOptionalNotes(Object? data) {
  if (data is! Map) return const [];
  final caps = data['capabilities'];
  final optional = caps is Map ? caps['optional'] : null;
  if (optional is! Map) return const [];
  return [
    for (final e in optionalCapabilityNotes.entries)
      if (optional[e.key] == false) e.value,
  ];
}

/// One sentence that names the [missing] capabilities in plain words.
String missingCapabilitiesSentence(List<String> missing) {
  final words = [
    for (final m in missing) (capabilityWords[m] ?? m.replaceAll('_', ' ')),
  ];
  return 'Tefteri needs a feature that your task app does not offer: '
      '${words.join('; ')}.';
}

/// Tells the user which required capabilities the task app lacks and that the
/// connection was not made.
Future<void> showMissingCapabilities(BuildContext context,
    {required String appName, required List<String> missing}) {
  final text = Theme.of(context).textTheme;
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const Key('missing-capability'),
      title: const Text('This task app cannot be used yet'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tefteri did not connect $appName, because it lacks '
                  'something Tefteri needs:'),
              const SizedBox(height: 8),
              for (final m in missing)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                      '•  ${capabilityWords[m] ?? m.replaceAll('_', ' ')}',
                      key: Key('missing-$m')),
                ),
              const SizedBox(height: 8),
              Text(
                'Nothing was changed in your task app. Use a task app that '
                'offers this, or ask its maker to add it.',
                style: text.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          key: const Key('missing-capability-close'),
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
