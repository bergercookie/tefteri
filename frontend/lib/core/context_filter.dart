/// Global all/life/work filter shared by every view.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Work/life filter values; [name] matches the API's `context` parameter.
enum ContextFilter {
  /// Show everything.
  all,

  /// Personal items only.
  life,

  /// Work items only.
  work,
}

/// The currently selected filter.
final contextFilterProvider = StateProvider<ContextFilter>((_) => ContextFilter.all);
