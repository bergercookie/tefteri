/// Dialog to choose which calendars of a Google connection tefteri syncs.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/calendar_color.dart';
import '../../theme/theme.dart';
import 'calendar_choice.dart';
import 'connection_models.dart';

/// Shows the chooser for [connectionId]. Answers true when the user saved.
Future<bool> showCalendarChooser(
  BuildContext context, {
  required String connectionId,
  String? name,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) =>
        CalendarChooserDialog(connectionId: connectionId, name: name),
  );
  return saved == true;
}

/// Lists every calendar of a connection with a checkbox.
class CalendarChooserDialog extends ConsumerStatefulWidget {
  /// Creates the dialog.
  const CalendarChooserDialog(
      {required this.connectionId, this.name, super.key});

  /// The connection to choose for.
  final String connectionId;

  /// Name of the connection, for the message after saving.
  final String? name;

  @override
  ConsumerState<CalendarChooserDialog> createState() => _State();
}

class _State extends ConsumerState<CalendarChooserDialog> {
  static const _filterFrom = 8;

  Set<String>? _initial;
  Set<String> _chosen = {};
  String _filter = '';
  bool _saving = false;
  String? _error;

  void _init(List<CalendarInfo> list) {
    if (_initial != null) return;
    _initial = {
      for (final c in list)
        if (c.enabled) c.id
    };
    _chosen = {..._initial!};
  }

  bool get _changed => _initial != null && !setEquals(_initial!, _chosen);

  bool setEquals(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  Future<void> _save(List<CalendarInfo> list) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final ids = [
        for (final c in list)
          if (_chosen.contains(c.id)) c.id
      ];
      final r = await ref
          .read(calendarChoiceApiProvider)
          .save(widget.connectionId, ids);
      ref.invalidate(calendarCountProvider(widget.connectionId));
      ref.invalidate(calendarsProvider(widget.connectionId));
      if (r.syncFailed) {
        final reason = FailureReason.parse(r.syncReason).message;
        final detail = r.syncDetail;
        messenger.showSnackBar(SnackBar(
          key: const Key('connection-sync-failed'),
          duration: const Duration(seconds: 12),
          content: Text('${widget.name ?? 'The connection'} saved your '
              'choice, but the sync failed. '
              '$reason${detail == null || detail.isEmpty ? '' : ' $detail'}'),
        ));
      } else {
        messenger.showSnackBar(
            const SnackBar(content: Text('Saved your calendar choice.')));
      }
      navigator.pop(true);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = apiErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final calendars = ref.watch(calendarsProvider(widget.connectionId));
    final list = calendars.valueOrNull;
    if (list != null) _init(list);
    return AlertDialog(
      key: const Key('calendar-chooser'),
      title: const Text('Choose calendars'),
      content: SizedBox(
        width: 420,
        child: calendars.when(
          loading: () => const SizedBox(height: 160, child: Loading()),
          error: (_, __) => EmptyState(
            icon: Icons.calendar_month_outlined,
            message: 'Cannot load the calendars.',
            action: TextButton(
              key: const Key('calendar-chooser-retry'),
              onPressed: () =>
                  ref.invalidate(calendarsProvider(widget.connectionId)),
              child: const Text('Retry'),
            ),
          ),
          data: (list) => list.isEmpty
              ? const EmptyState(
                  icon: Icons.calendar_month_outlined,
                  message: 'This account has no calendars.')
              : _body(context, list),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('calendar-chooser-cancel'),
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('calendar-chooser-save'),
          onPressed:
              (_changed && !_saving && list != null) ? () => _save(list) : null,
          child: Text(_saving ? 'Saving...' : 'Save'),
        ),
      ],
    );
  }

  Widget _body(BuildContext context, List<CalendarInfo> list) {
    final shown = [
      for (final c in list)
        if (c.name.toLowerCase().contains(_filter.toLowerCase())) c,
    ];
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (list.length > _filterFrom)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: TextField(
              key: const Key('calendar-chooser-filter'),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search calendars',
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
        Wrap(children: [
          TextButton(
            key: const Key('calendar-chooser-all'),
            onPressed: () =>
                setState(() => _chosen = {for (final c in list) c.id}),
            child: const Text('Select all'),
          ),
          TextButton(
            key: const Key('calendar-chooser-none'),
            onPressed: () => setState(() => _chosen = {}),
            child: const Text('Select none'),
          ),
        ]),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final c in shown)
                CheckboxListTile(
                  key: Key('calendar-option-${c.id}'),
                  value: _chosen.contains(c.id),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  onChanged: _saving
                      ? null
                      : (v) => setState(() =>
                          v == true ? _chosen.add(c.id) : _chosen.remove(c.id)),
                  title: Row(children: [
                    Container(
                      key: Key('calendar-dot-${c.id}'),
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: parseCalendarColor(c.color) ?? muted,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    Expanded(child: Text(c.name)),
                  ]),
                  subtitle: c.readOnly
                      ? Text('Read only',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: muted))
                      : null,
                ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: Text(_error!,
                key: const Key('calendar-chooser-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
      ],
    );
  }
}
