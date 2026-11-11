/// The dialogs of the weekly review that change a milestone: close it and
/// return its open tasks to the theme, and mark it done by hand. Both show
/// their effect first. A close can be undone by reopening the milestone.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../theme/theme.dart';
import 'weekly_api.dart';
import 'weekly_models.dart';
import 'weekly_widgets.dart';

/// Shows the close dialog; answers the result when the milestone was closed,
/// else null.
Future<CloseResult?> showCloseDialog(BuildContext context,
        {required String milestoneId, required String name}) =>
    showDialog<CloseResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CloseDialog(milestoneId: milestoneId, name: name),
    );

enum _Phase { loading, preview, moving, failed, done, error }

/// Shows how many open tasks will move and where, asks to confirm, moves
/// them, and shows the result. A failure part way lists the tasks that
/// already moved and offers a retry.
class CloseDialog extends ConsumerStatefulWidget {
  /// Creates the dialog for the milestone [milestoneId] called [name].
  const CloseDialog({required this.milestoneId, required this.name, super.key});

  /// Id of the milestone.
  final String milestoneId;

  /// Its name.
  final String name;

  @override
  ConsumerState<CloseDialog> createState() => _CloseDialogState();
}

class _CloseDialogState extends ConsumerState<CloseDialog> {
  _Phase _phase = _Phase.loading;
  ClosePreview? _preview;
  CloseResult? _result;
  CloseFailure? _failure;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _phase = _Phase.loading);
    try {
      final p =
          await ref.read(weeklyApiProvider).closePreview(widget.milestoneId);
      if (!mounted) return;
      setState(() {
        _preview = p;
        _phase = _Phase.preview;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = apiErrorMessage(e);
        _phase = _Phase.error;
      });
    }
  }

  Future<void> _confirm() async {
    setState(() => _phase = _Phase.moving);
    try {
      final r =
          await ref.read(weeklyApiProvider).closeMilestone(widget.milestoneId);
      if (!mounted) return;
      setState(() {
        _result = r;
        _phase = _Phase.done;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _failure = CloseFailure.fromBody(e.response?.data, apiErrorMessage(e));
        _phase = _Phase.failed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final theme = _preview?.themeName ?? '';
    final (Widget body, List<Widget> actions) = switch (_phase) {
      _Phase.loading => (
          const Padding(padding: EdgeInsets.all(Space.lg), child: Loading()),
          <Widget>[
            TextButton(
              key: const Key('close-cancel'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ]
        ),
      _Phase.error => (
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_error, key: const Key('close-error')),
              const SizedBox(height: Space.sm),
              Text('Nothing was moved or closed.', style: text.bodySmall),
            ],
          ),
          <Widget>[
            TextButton(
              key: const Key('close-cancel'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('close-reload'),
              onPressed: _load,
              child: const Text('Try again'),
            ),
          ]
        ),
      _Phase.preview => (
          _previewBody(context, text),
          <Widget>[
            TextButton(
              key: const Key('close-cancel'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('close-confirm'),
              onPressed: _confirm,
              child: Text(_preview!.openTasks == 0
                  ? 'Close the milestone'
                  : 'Move ${plural(_preview!.openTasks, 'task')} and close'),
            ),
          ]
        ),
      _Phase.moving => (
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                  padding: EdgeInsets.all(Space.lg), child: Loading()),
              Text('Moving tasks to $theme...',
                  key: const Key('close-progress'), style: text.bodyMedium),
            ],
          ),
          const <Widget>[]
        ),
      _Phase.failed => (
          _failureBody(context, text, scheme),
          <Widget>[
            TextButton(
              key: const Key('close-cancel'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close this window'),
            ),
            FilledButton(
              key: const Key('close-retry'),
              onPressed: _confirm,
              child: const Text('Try again'),
            ),
          ]
        ),
      _Phase.done => (
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _result!.moved == 0
                    ? 'Closed. No task had to move.'
                    : 'Closed. ${plural(_result!.moved, 'task')} moved to '
                        '$theme.',
                key: const Key('close-result'),
                style: text.titleSmall,
              ),
              const SizedBox(height: Space.sm),
              Text(
                'To undo it, reopen the milestone. Tasks you did not change '
                'since then move back.',
                style: text.bodySmall,
              ),
            ],
          ),
          <Widget>[
            FilledButton(
              key: const Key('close-done'),
              onPressed: () => Navigator.of(context).pop(_result),
              child: const Text('Done'),
            ),
          ]
        ),
    };
    return AlertDialog(
      key: const Key('close-dialog'),
      title: Text('Close "${widget.name}"'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(child: body),
      ),
      actions: actions,
    );
  }

  Widget _previewBody(BuildContext context, TextTheme text) {
    final p = _preview!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          p.openTasks == 0
              ? 'No open task has to move. The milestone is closed and nothing '
                  'else changes.'
              : '${plural(p.openTasks, 'open task')} will move to '
                  '${p.themeName}.',
          key: const Key('close-effect'),
          style: text.titleSmall,
        ),
        const SizedBox(height: Space.sm),
        Text(
          'The milestone is closed only after every task has moved. You can '
          'undo this later: reopen the milestone and the tasks that you did '
          'not change since then move back.',
          key: const Key('close-undo-note'),
          style: text.bodySmall,
        ),
      ],
    );
  }

  Widget _failureBody(
      BuildContext context, TextTheme text, ColorScheme scheme) {
    final f = _failure!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(f.message,
            key: const Key('close-failure'),
            style: text.bodyMedium?.copyWith(color: scheme.error)),
        const SizedBox(height: Space.sm),
        Text(
          'The milestone is not closed.'
          '${f.remaining > 0 ? ' ${plural(f.remaining, 'task')} still to move.' : ''}'
          ' It is safe to try again: tasks that moved already stay where they '
          'are.',
          style: text.bodyMedium,
        ),
        if (f.moved.isNotEmpty) ...[
          const SizedBox(height: Space.sm),
          Text('Already moved:', style: text.titleSmall),
          for (final t in f.moved)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text(t.title,
                  key: Key('moved-${t.taskId}'), style: text.bodyMedium),
            ),
        ],
      ],
    );
  }
}

/// Shows the effect of marking [milestoneId] done by hand and asks to confirm.
/// Answers true when the user confirms. Nothing is written here: the mark is
/// sent when the review is saved. [milestoneId] may be null for an old entry.
Future<bool> showMarkDoneDialog(BuildContext context,
    {required String name, String? milestoneId}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => MarkDoneDialog(name: name, milestoneId: milestoneId),
  );
  return ok == true;
}

/// Says that marking done moves and deletes nothing, and how many open tasks
/// stay where they are.
class MarkDoneDialog extends ConsumerStatefulWidget {
  /// Creates the dialog.
  const MarkDoneDialog({required this.name, this.milestoneId, super.key});

  /// The milestone name.
  final String name;

  /// Its id; null for an entry from before milestones.
  final String? milestoneId;

  @override
  ConsumerState<MarkDoneDialog> createState() => _MarkDoneDialogState();
}

class _MarkDoneDialogState extends ConsumerState<MarkDoneDialog> {
  static const _fallback = 'Nothing is moved or deleted. Its open tasks stay '
      'in the project.';
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.milestoneId;
    if (id == null) return;
    try {
      final p = await ref.read(weeklyApiProvider).doneEffect(id);
      if (mounted && p.message.isNotEmpty) setState(() => _message = p.message);
    } on DioException {
      // The fixed sentence says the same.
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      key: const Key('mark-done-dialog'),
      title: Text('Mark "${widget.name}" as done?'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_message ?? _fallback,
                key: const Key('mark-done-effect'), style: text.bodyMedium),
            const SizedBox(height: Space.sm),
            Text(
              'The milestone counts as done on the day you save the review. '
              'You can take the mark back before you save.',
              style: text.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('mark-done-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('mark-done-confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Mark as done'),
        ),
      ],
    );
  }
}

/// What a reopen did: how many tasks moved back and which could not.
class ReopenNotice extends StatelessWidget {
  /// Creates the notice.
  const ReopenNotice({required this.result, required this.id, super.key});

  /// The answer of the reopen.
  final ReopenResult result;

  /// Id that makes the keys unique (the plan project id).
  final String id;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final n = result.notMovedBack.length;
    return Notice(
      key: Key('reopen-result-$id'),
      icon: Icons.undo,
      message: result.movedBack == 0
          ? 'Reopened. It is active again.'
          : 'Reopened. ${plural(result.movedBack, 'task')} moved back.',
      below: n == 0
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '${plural(n, 'task')} could not move back and '
                    '${n == 1 ? 'stays' : 'stay'} where '
                    '${n == 1 ? 'it is' : 'they are'}:',
                    style: text.titleSmall),
                for (final t in result.notMovedBack)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.xs),
                    child: Text('${t.title}: ${t.reasonLine}',
                        key: Key('not-moved-${t.taskId}'),
                        style: text.bodyMedium),
                  ),
              ],
            ),
    );
  }
}
