/// The work mark of a project that a page knows only by its id.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/work_mark.dart';
import 'projects_api.dart';

/// Shows the briefcase (or, with [pill], the pill "Work") when the project
/// [projectId] is work: a theme that the user marked, or a project under one.
/// It shows nothing while the answer loads, when the project is not work, and
/// when the call fails.
class WorkTag extends ConsumerWidget {
  /// Creates the tag for the project with the label-row id [projectId].
  const WorkTag({required this.projectId, this.pill = false, super.key});

  /// The id of the project, as the project API names it.
  final String projectId;

  /// Show the pill with the word, not the small briefcase.
  final bool pill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final work =
        ref.watch(workProjectIdsProvider).valueOrNull?.contains(projectId) ??
            false;
    if (!work) return const SizedBox.shrink();
    return pill
        ? WorkPill(key: Key('work-pill-$projectId'))
        : WorkIcon(key: Key('work-icon-$projectId'));
  }
}
