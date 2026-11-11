/// Creates a milestone under a theme: a name and a done-state.
library;

import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import 'weekly_models.dart';

/// What the user typed to create a milestone.
typedef NewMilestone = ({String parentId, String name, String doneState});

/// Asks for the theme, the name and the done-state of a new milestone.
///
/// [save] creates it and answers the error message, or null when it worked;
/// the dialog closes on success. On an error the dialog stays open with
/// everything the user typed, and says what happened.
class NewMilestoneDialog extends StatefulWidget {
  /// Creates the dialog. [initialParent] is a theme's project id.
  const NewMilestoneDialog(
      {required this.themes,
      required this.save,
      this.initialParent,
      super.key});

  /// The themes the milestone can go under.
  final List<ThemeGroup> themes;

  /// The theme to start with.
  final String? initialParent;

  /// Creates the milestone; answers an error message, or null.
  final Future<String?> Function(NewMilestone milestone) save;

  @override
  State<NewMilestoneDialog> createState() => _NewMilestoneDialogState();
}

class _NewMilestoneDialogState extends State<NewMilestoneDialog> {
  final _name = TextEditingController();
  final _done = TextEditingController();
  late String _parent = widget.themes
          .where((t) => t.containerId == widget.initialParent)
          .firstOrNull
          ?.containerId ??
      widget.themes.first.containerId;
  String? _doneHint;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _done.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final done = _done.text.trim();
    if (name.isEmpty || _busy) return;
    if (done.isEmpty) {
      setState(() => _doneHint =
          'Say when this milestone is finished, in one sentence. For example: '
              '"Ship the login flow". Your text is kept.');
      return;
    }
    setState(() {
      _busy = true;
      _doneHint = null;
      _error = null;
    });
    final message =
        await widget.save((parentId: _parent, name: name, doneState: done));
    if (!mounted) return;
    if (message == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _busy = false;
        _error = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      key: const Key('new-milestone-dialog'),
      title: const Text('New milestone'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                key: const Key('milestone-theme'),
                initialValue: _parent,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Under theme'),
                items: [
                  for (final t in widget.themes)
                    DropdownMenuItem(value: t.containerId, child: Text(t.name)),
                ],
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _parent = v ?? _parent),
              ),
              const SizedBox(height: Space.md),
              TextField(
                key: const Key('milestone-name'),
                controller: _name,
                autofocus: true,
                enabled: !_busy,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                    labelText: 'Name', hintText: 'Login flow'),
              ),
              const SizedBox(height: Space.md),
              TextField(
                key: const Key('milestone-done-state'),
                controller: _done,
                enabled: !_busy,
                minLines: 1,
                maxLines: 3,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: 'Done when',
                  hintText: 'Users can sign in with a passkey',
                ),
              ),
              const SizedBox(height: Space.xs),
              Text(
                _doneHint ??
                    'The done-state is one sentence that says when the '
                        'milestone is finished, like "ship the login flow".',
                key: Key(_doneHint == null
                    ? 'milestone-done-example'
                    : 'milestone-done-hint'),
                style: text.bodySmall
                    ?.copyWith(color: _doneHint == null ? null : scheme.error),
              ),
              const SizedBox(height: Space.sm),
              Text(
                'It is created in your task app, and you add its tasks '
                'after that.',
                style: text.bodySmall,
              ),
              if (_error != null) ...[
                const SizedBox(height: Space.sm),
                Text(_error!,
                    key: const Key('milestone-error'),
                    style: text.bodyMedium?.copyWith(color: scheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('milestone-cancel'),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('milestone-create'),
          onPressed: _name.text.trim().isEmpty || _busy ? null : _submit,
          child: Text(_busy ? 'Creating...' : 'Create and add'),
        ),
      ],
    );
  }
}
