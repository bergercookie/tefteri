/// State of the Projects screen: the classification and the recent changes.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'projects_api.dart';
import 'projects_models.dart';

/// A change the user can still undo.
class RecentChange {
  /// Creates an entry. A label change has a [batchId]; an archive has the
  /// [archivedId] of the project.
  RecentChange(this.text, {this.batchId, this.archivedId});

  /// What happened, in a short sentence.
  final String text;

  /// The label batch to undo.
  final String? batchId;

  /// The archived project to restore.
  final String? archivedId;

  /// True once undone.
  bool undone = false;
}

/// The changes made on the Projects screen, newest first. They stay for the
/// session, so Undo is still there after the snackbar has gone.
class RecentChanges extends StateNotifier<List<RecentChange>> {
  /// Creates an empty list.
  RecentChanges() : super(const []);

  /// Adds [c] at the top; keeps the last five.
  void add(RecentChange c) => state = [c, ...state].take(5).toList();

  /// Marks [c] as undone.
  void markUndone(RecentChange c) {
    c.undone = true;
    state = [...state];
  }
}

/// The recent changes of this session.
final recentChangesProvider =
    StateNotifierProvider<RecentChanges, List<RecentChange>>(
        (_) => RecentChanges());

/// Loads the classification and makes the changes of the Projects screen.
/// A write that fails throws [DioException]; the screen shows the message.
class ClassificationController
    extends StateNotifier<AsyncValue<Classification>> {
  /// Creates the controller and loads the projects.
  ClassificationController(this._api, this._recent)
      : super(const AsyncLoading()) {
    load();
  }

  final ProjectsApi _api;
  final RecentChanges _recent;

  /// Loads the projects; keeps what is shown when a reload fails.
  Future<void> load() async {
    try {
      final c = await _api.classification();
      if (mounted) state = AsyncData(c);
    } on DioException catch (e, st) {
      if (mounted && !state.hasValue) state = AsyncError(e, st);
    }
  }

  /// The effect of [changes], without saving them.
  Future<LabelEffect> preview(List<LabelChange> changes,
          {String source = 'user'}) async =>
      (await _api.saveLabels(changes, dryRun: true, source: source)).effect;

  /// Saves [changes] and remembers them for undo under [summary]. Answers the
  /// entry to undo them.
  Future<RecentChange?> save(List<LabelChange> changes,
      {String source = 'user', required String summary}) async {
    final r = await _api.saveLabels(changes, source: source);
    final id = r.batchId;
    final change = id == null ? null : RecentChange(summary, batchId: id);
    if (change != null) _recent.add(change);
    // Show the new labels at once; the reload that follows corrects the
    // derived values (parent theme, eligibility).
    final current = state.valueOrNull;
    if (mounted && current != null) {
      state = AsyncData(
          current.withLabels({for (final c in changes) c.id: c.label}));
    }
    unawaited(load());
    return change;
  }

  /// Undoes [change]: restores the labels, or the archived project.
  Future<void> undo(RecentChange change) async {
    final batch = change.batchId;
    final archived = change.archivedId;
    if (batch != null) await _api.undo(batch);
    if (archived != null) await _api.restore(archived);
    _recent.markUndone(change);
    await load();
  }

  /// Renames project [id] in the task app and here.
  Future<void> rename(String id, String name) async {
    await _api.rename(id, name);
    await load();
  }

  /// Creates a project in the task app and labels it.
  Future<void> create(
      {required String connectionId,
      required String name,
      String? parentId,
      required ProjectLabel label}) async {
    await _api.create(
        connectionId: connectionId,
        name: name,
        parentId: parentId,
        label: label);
    await load();
  }

  /// Archives project [id]; the project stays in Tefteri as orphaned.
  Future<RecentChange> archive(ClassifiedProject p) async {
    await _api.archive(p.id);
    final change = RecentChange('Archived "${p.name}".', archivedId: p.id);
    _recent.add(change);
    await load();
    return change;
  }

  /// Restores archived project [id].
  Future<void> restore(String id) async {
    await _api.restore(id);
    await load();
  }
}

/// The classification of the signed-in user.
final classificationProvider = StateNotifierProvider.autoDispose<
    ClassificationController, AsyncValue<Classification>>(
  (ref) => ClassificationController(
      ref.watch(projectsApiProvider), ref.read(recentChangesProvider.notifier)),
);
