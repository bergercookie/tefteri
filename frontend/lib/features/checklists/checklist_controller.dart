/// Loads and ticks the checklist of one week, month or year.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/planning_api.dart';
import '../../core/planning_models.dart';

/// Which checklist: a kind and a day in its period (`YYYY-MM-DD`).
typedef ChecklistKey = ({ChecklistKind kind, String day});

/// Keeps the checklist of one period and writes the ticks.
///
/// A tick shows at once and is written to the server; if the server refuses,
/// the item goes back and the message is returned. Ticks are sent one after
/// the other, so a quick second tap cannot overtake the first.
class ChecklistController extends StateNotifier<AsyncValue<PeriodChecklist>> {
  /// Creates the controller and loads the checklist.
  ChecklistController(this._api, this._key) : super(const AsyncLoading()) {
    load();
  }

  final PlanningApi _api;
  final ChecklistKey _key;
  Future<void> _queue = Future.value();

  DateTime get _day => DateTime.parse(_key.day);

  /// Reads the checklist from the server.
  Future<void> load() async {
    state = const AsyncLoading();
    try {
      final c = await _api.checklist(_key.kind, _day);
      if (mounted) state = AsyncData(c);
    } on Object catch (e, st) {
      if (mounted) state = AsyncError(e, st);
    }
  }

  /// Ticks or unticks [text]. Returns an error message, or null.
  Future<String?> tick(String text, bool checked) {
    final before = state.valueOrNull;
    if (before == null) return Future.value(null);
    state = AsyncData(before.withTick(text, checked));
    final result = _queue.then<String?>((_) async {
      try {
        final fresh =
            await _api.tickChecklistItem(_key.kind, _day, text, checked);
        // The last answer in the line is the one to show: an older one would
        // undo a tick that was made after it.
        if (mounted && _pending == 1) state = AsyncData(fresh);
        return null;
      } on Object catch (e) {
        if (mounted) {
          state =
              AsyncData((state.valueOrNull ?? before).withTick(text, !checked));
        }
        return apiErrorMessage(e);
      } finally {
        _pending--;
      }
    });
    _pending++;
    _queue = result.then((_) {});
    return result;
  }

  int _pending = 0;
}

/// The checklist of one week, month or year.
final checklistProvider = StateNotifierProvider.autoDispose
    .family<ChecklistController, AsyncValue<PeriodChecklist>, ChecklistKey>(
  (ref, key) => ChecklistController(ref.watch(planningApiProvider), key),
);
