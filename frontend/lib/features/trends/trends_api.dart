/// The call that lists the numbers of the weeks.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'trends_models.dart';

/// The numbers of the last [weeks] weeks, the running week last, from
/// `GET /weekly/trends`.
final trendsProvider = FutureProvider.autoDispose
    .family<List<WeekMetrics>, int>((ref, weeks) async {
  final r = await ref
      .watch(dioProvider)
      .get<Object?>('/weekly/trends', queryParameters: {'weeks': weeks});
  final body = r.data! as Map<String, dynamic>;
  return [
    for (final w in (body['weeks'] as List? ?? const []))
      WeekMetrics.fromJson(w as Map<String, dynamic>),
  ];
});
