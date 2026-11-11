/// Models of project classification, as the backend sends them.
library;

import 'package:flutter/foundation.dart';

/// What a project is for. The API calls Routine "maintenance"; the screen
/// shows "Routine".
enum ProjectLabel {
  /// A long-running home for related work.
  theme('theme', 'Theme', 'Themes'),

  /// A small outcome that can be finished in a week.
  milestone('milestone', 'Milestone', 'Milestones'),

  /// Routine work with no end.
  maintenance('maintenance', 'Routine', 'Routines'),

  /// Hidden from planning.
  ignored('ignored', 'Ignored', 'Ignored');

  const ProjectLabel(this.api, this.title, this.plural);

  /// The value in the API.
  final String api;

  /// The word the user sees.
  final String title;

  /// The group name the user sees.
  final String plural;

  /// One plain sentence that explains the label.
  String get sentence => switch (this) {
        ProjectLabel.theme => 'A long-running home for related work.',
        ProjectLabel.milestone =>
          'A small outcome you can finish in about a week.',
        ProjectLabel.maintenance =>
          'Work that repeats and never finishes, like chores or admin.',
        ProjectLabel.ignored => 'Hidden from planning.',
      };

  /// Parses the API value; null for none or an unknown value.
  static ProjectLabel? parse(Object? value) {
    for (final l in values) {
      if (l.api == value) return l;
    }
    return null;
  }
}

/// The word for a label as the effect of a change names it (`none` means no
/// label yet).
String labelWord(Object? value) =>
    ProjectLabel.parse(value)?.title ?? 'Unsorted';

/// Why Tefteri suggests a label.
enum ProposalReason {
  /// The project is at the top level.
  topLevel,

  /// The project sits inside another project.
  nested,

  /// The project was in a past weekly plan.
  wasCommitted,

  /// The project sits inside a routine project.
  insideRoutine;

  /// Parses the API value.
  static ProposalReason parse(Object? value) => switch (value) {
        'top_level' => ProposalReason.topLevel,
        'was_committed' => ProposalReason.wasCommitted,
        'inside_routine' => ProposalReason.insideRoutine,
        _ => ProposalReason.nested,
      };
}

/// A suggested label. It is only a suggestion until the user saves it.
@immutable
class Proposal {
  /// Creates a proposal.
  const Proposal(this.label, this.reason);

  /// Parses a proposal JSON object.
  factory Proposal.fromJson(Object? j) {
    final m = j is Map ? j : const {};
    return Proposal(ProjectLabel.parse(m['label']) ?? ProjectLabel.milestone,
        ProposalReason.parse(m['reason']));
  }

  /// The suggested label.
  final ProjectLabel label;

  /// Why.
  final ProposalReason reason;

  /// The reason in plain words.
  String get because => switch (reason) {
        ProposalReason.topLevel => 'it is at the top level',
        ProposalReason.nested => 'it sits inside another project',
        ProposalReason.wasCommitted => 'you planned it in a past week',
        ProposalReason.insideRoutine => 'it sits inside a routine project',
      };
}

/// Why a project is no longer live.
enum OrphanReason {
  /// The task app no longer lists it.
  missing,

  /// The user archived it from Tefteri.
  archived;

  /// Parses the API value.
  static OrphanReason parse(Object? value) =>
      value == 'archived' ? OrphanReason.archived : OrphanReason.missing;
}

/// A project that is not live in the task app.
@immutable
class Orphaned {
  /// Creates the state.
  const Orphaned(this.reason, this.at);

  /// Parses the `orphaned` JSON object.
  static Orphaned? fromJson(Object? j) => j is Map
      ? Orphaned(OrphanReason.parse(j['reason']),
          DateTime.tryParse('${j['at'] ?? ''}'))
      : null;

  /// Why it is orphaned.
  final OrphanReason reason;

  /// Since when.
  final DateTime? at;

  /// The reason in plain words.
  String get explanation => switch (reason) {
        OrphanReason.missing =>
          'No longer in your task app. It was deleted or moved out of reach '
              'there. Tefteri keeps its name, label and history.',
        OrphanReason.archived =>
          'Archived from Tefteri. It is hidden from planning, and Tefteri '
              'keeps its label and history.',
      };
}

/// One project in the classification tree.
@immutable
class ClassifiedProject {
  /// Creates a project.
  const ClassifiedProject({
    required this.id,
    required this.name,
    this.parentId,
    this.label,
    required this.proposal,
    required this.effectiveLabel,
    this.parentThemeId,
    this.unsorted = false,
    this.orphaned,
    this.eligible = true,
    this.openTasks = 0,
    this.subprojects = 0,
    this.inCommittedPlan = false,
  });

  /// Parses a project JSON object.
  factory ClassifiedProject.fromJson(Map<String, dynamic> j) {
    final label = ProjectLabel.parse(j['label']);
    final proposal = Proposal.fromJson(j['proposal']);
    return ClassifiedProject(
      id: '${j['id']}',
      name: '${j['name'] ?? ''}',
      parentId: j['parent_id'] as String?,
      label: label,
      proposal: proposal,
      effectiveLabel:
          ProjectLabel.parse(j['effective_label']) ?? label ?? proposal.label,
      parentThemeId: j['parent_theme_id'] as String?,
      unsorted: j['unsorted'] == true || label == null,
      orphaned: Orphaned.fromJson(j['orphaned']),
      eligible: j['eligible'] != false,
      openTasks: (j['open_tasks'] as num? ?? 0).toInt(),
      subprojects: (j['subprojects'] as num? ?? 0).toInt(),
      inCommittedPlan: j['in_committed_plan'] == true,
    );
  }

  /// The id of the project in Tefteri's API.
  final String id;

  /// The last known title.
  final String name;

  /// The parent project, or null at the top level.
  final String? parentId;

  /// The saved label; null while the project is unsorted.
  final ProjectLabel? label;

  /// The suggestion. Present for every project.
  final Proposal proposal;

  /// The saved label, or the suggestion while unsorted.
  final ProjectLabel effectiveLabel;

  /// The nearest ancestor that is a theme, or null (no theme).
  final String? parentThemeId;

  /// True while the project has no saved label.
  final bool unsorted;

  /// Set when the project is not live in the task app.
  final Orphaned? orphaned;

  /// Whether planning pickers may offer the project.
  final bool eligible;

  /// Open tasks in the project.
  final int openTasks;

  /// Projects directly inside it.
  final int subprojects;

  /// Whether a committed weekly plan holds it.
  final bool inCommittedPlan;

  /// Copy with a new saved [label] (null: unsorted).
  ClassifiedProject withLabel(ProjectLabel? label) => ClassifiedProject(
        id: id,
        name: name,
        parentId: parentId,
        label: label,
        proposal: proposal,
        effectiveLabel: label ?? proposal.label,
        parentThemeId: parentThemeId,
        unsorted: label == null,
        orphaned: orphaned,
        eligible: eligible,
        openTasks: openTasks,
        subprojects: subprojects,
        inCommittedPlan: inCommittedPlan,
      );
}

/// The projects of one task connection.
@immutable
class ConnectionProjects {
  /// Creates the list.
  const ConnectionProjects({
    required this.connectionId,
    required this.name,
    this.canRename = false,
    this.canRestore = false,
    this.projects = const [],
  });

  /// Parses one item of `connections`.
  factory ConnectionProjects.fromJson(Map<String, dynamic> j) {
    final caps = j['capabilities'] is Map ? j['capabilities'] as Map : const {};
    return ConnectionProjects(
      connectionId: '${j['connection_id']}',
      name: '${j['name'] ?? ''}',
      canRename: caps['rename'] == true,
      canRestore: caps['restore'] == true,
      projects: [
        for (final p in (j['projects'] as List? ?? const []))
          ClassifiedProject.fromJson(p as Map<String, dynamic>),
      ],
    );
  }

  /// Connection id.
  final String connectionId;

  /// Connection name.
  final String name;

  /// Whether the task app can rename projects.
  final bool canRename;

  /// Whether the task app can restore archived projects.
  final bool canRestore;

  /// The projects, in tree order.
  final List<ClassifiedProject> projects;
}

/// The answer of `GET /projects/classification`.
@immutable
class Classification {
  /// Creates the answer.
  const Classification({this.connections = const [], this.unsortedCount = 0});

  /// Parses the answer.
  factory Classification.fromJson(Map<String, dynamic> j) => Classification(
        connections: [
          for (final c in (j['connections'] as List? ?? const []))
            ConnectionProjects.fromJson(c as Map<String, dynamic>),
        ],
        unsortedCount: (j['unsorted_count'] as num? ?? 0).toInt(),
      );

  /// One entry per task connection.
  final List<ConnectionProjects> connections;

  /// Projects without a saved label, over all connections.
  final int unsortedCount;

  /// True when no connection holds a project.
  bool get hasNoProjects => connections.every((c) => c.projects.isEmpty);

  /// The project [id], or null.
  ClassifiedProject? project(String id) {
    for (final c in connections) {
      for (final p in c.projects) {
        if (p.id == id) return p;
      }
    }
    return null;
  }

  /// Copy in which the projects [labels] (id to label) have the new labels.
  Classification withLabels(Map<String, ProjectLabel?> labels) {
    var unsorted = 0;
    final next = [
      for (final c in connections)
        ConnectionProjects(
          connectionId: c.connectionId,
          name: c.name,
          canRename: c.canRename,
          canRestore: c.canRestore,
          projects: [
            for (final p in c.projects)
              labels.containsKey(p.id) ? p.withLabel(labels[p.id]) : p,
          ],
        ),
    ];
    for (final c in next) {
      unsorted +=
          c.projects.where((p) => p.label == null && p.orphaned == null).length;
    }
    return Classification(connections: next, unsortedCount: unsorted);
  }
}

/// One label to save.
@immutable
class LabelChange {
  /// Creates a change; a null [label] sets the project back to unsorted.
  const LabelChange(this.id, this.label);

  /// Project id.
  final String id;

  /// The new label.
  final ProjectLabel? label;

  /// The JSON body item.
  Map<String, Object?> toJson() => {'id': id, 'label': label?.api};
}

/// How many projects change from one label to another.
@immutable
class ChangeCount {
  /// Creates the count.
  const ChangeCount(this.from, this.to, this.count);

  /// Parses an item of `by_change`.
  factory ChangeCount.fromJson(Map<String, dynamic> j) => ChangeCount(
      '${j['from'] ?? 'none'}',
      '${j['to'] ?? 'none'}',
      (j['count'] as num? ?? 0).toInt());

  /// The old label (`none` for unsorted).
  final String from;

  /// The new label (`none` for unsorted).
  final String to;

  /// Projects with this change.
  final int count;
}

/// What a bulk change does.
@immutable
class LabelEffect {
  /// Creates the effect.
  const LabelEffect(
      {this.changed = 0, this.byChange = const [], this.inCommittedPlan = 0});

  /// Parses an `effect` JSON object.
  factory LabelEffect.fromJson(Object? j) {
    final m = j is Map ? j : const {};
    return LabelEffect(
      changed: (m['changed'] as num? ?? 0).toInt(),
      byChange: [
        for (final c in (m['by_change'] as List? ?? const []))
          ChangeCount.fromJson(c as Map<String, dynamic>),
      ],
      inCommittedPlan: (m['in_committed_plan'] as num? ?? 0).toInt(),
    );
  }

  /// Projects that change.
  final int changed;

  /// The changes, counted by old and new label.
  final List<ChangeCount> byChange;

  /// Projects that a committed plan holds.
  final int inCommittedPlan;
}

/// The answer of `PUT /projects/labels`.
@immutable
class SaveResult {
  /// Creates the result.
  const SaveResult(this.batchId, this.effect);

  /// Parses the answer.
  factory SaveResult.fromJson(Map<String, dynamic> j) =>
      SaveResult(j['batch_id'] as String?, LabelEffect.fromJson(j['effect']));

  /// The id to undo this save, or null for a dry run.
  final String? batchId;

  /// The effect.
  final LabelEffect effect;
}
