/// State of the annual review screen.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'annual_review_api.dart';
import 'annual_review_models.dart';

/// Loads one year's review and writes its notes. A failed write throws
/// [DioException]; the screen shows the message and nothing changes.
class AnnualReviewController extends StateNotifier<AsyncValue<AnnualReview>> {
  /// Creates the controller and loads [year].
  AnnualReviewController(this._api, this.year) : super(const AsyncLoading()) {
    load();
  }

  final AnnualReviewApi _api;

  /// The planning year.
  final int year;

  /// Loads the review; keeps what is shown when a reload fails.
  Future<void> load() async {
    try {
      final review = await _api.review(year);
      if (mounted) state = AsyncData(review);
    } on DioException catch (e, st) {
      if (mounted && !state.hasValue) state = AsyncError(e, st);
    }
  }

  /// Shows the loading state and loads again.
  Future<void> retry() async {
    state = const AsyncLoading();
    await load();
  }

  /// Creates or replaces the note of the year or of one goal.
  Future<ReviewNote> putNote({String? goalId, required String body}) async {
    final note = await _api.putNote(year, goalId: goalId, body: body);
    await load();
    return note;
  }

  /// Deletes a note and returns the text that was lost, for undo.
  Future<ReviewNote> deleteNote({String? goalId}) async {
    final note = await _api.deleteNote(year, goalId: goalId);
    await load();
    return note;
  }
}

/// The review of one year.
final annualReviewProvider = StateNotifierProvider.autoDispose
    .family<AnnualReviewController, AsyncValue<AnnualReview>, int>(
  (ref, year) =>
      AnnualReviewController(ref.watch(annualReviewApiProvider), year),
);
