/// Turns the classification into the rows of the Projects screen: the groups,
/// the theme tree, search and collapsing. Pure code, so it is easy to test.
library;

import 'projects_models.dart';

/// The groups of the screen, in order.
enum GroupKind {
  /// No saved label yet.
  unsorted('Unsorted'),

  /// Themes, with their milestones inside.
  themes('Themes'),

  /// Milestones whose parent is not a theme.
  noThemeMilestones('Milestones without a theme'),

  /// Routine (maintenance) projects.
  routines('Routines'),

  /// Hidden from planning.
  ignored('Ignored'),

  /// Not live in the task app.
  orphaned('No longer in your task app');

  const GroupKind(this.title);

  /// The name the user sees.
  final String title;

  /// One plain sentence under the name.
  String get sentence => switch (this) {
        GroupKind.unsorted =>
          'You have not labelled these yet. Each one shows a suggestion: tap '
              'a label to choose, or accept all suggestions at once.',
        GroupKind.themes =>
          'A theme is a long-running home for related work. Milestones are '
              'small outcomes you can finish in a week, shown inside their '
              'theme.',
        GroupKind.noThemeMilestones =>
          'These milestones are not inside a theme. Move them under a theme '
              'in your task app, or change their label.',
        GroupKind.routines =>
          'Routines are work that repeats and never finishes, like chores or '
              'admin. Their tasks stay in your daily lists, but they are not '
              'offered when you plan a week.',
        GroupKind.ignored =>
          'Ignored projects are hidden from planning. They still sync, and '
              'you can bring them back with one tap.',
        GroupKind.orphaned =>
          'These projects were deleted in your task app, or you archived them '
              'here. Tefteri keeps their name, label and history.',
      };
}

/// One row of the screen.
sealed class TreeItem {
  const TreeItem();
}

/// The name of a task connection, shown when there is more than one.
class ConnectionItem extends TreeItem {
  /// Creates the heading.
  const ConnectionItem(this.name);

  /// Connection name.
  final String name;
}

/// The heading of a group.
class GroupItem extends TreeItem {
  /// Creates the heading.
  const GroupItem(this.kind, this.count, {required this.collapsed});

  /// Which group.
  final GroupKind kind;

  /// Projects in the group.
  final int count;

  /// Whether its projects are hidden.
  final bool collapsed;
}

/// A project row.
class ProjectItem extends TreeItem {
  /// Creates the row.
  const ProjectItem({
    required this.project,
    required this.connection,
    required this.group,
    this.depth = 0,
    this.hasChildren = false,
    this.collapsed = false,
    this.path = '',
    this.themeName,
  });

  /// The project.
  final ClassifiedProject project;

  /// The connection that holds it.
  final ConnectionProjects connection;

  /// The group it is shown in.
  final GroupKind group;

  /// Indent level in the theme tree.
  final int depth;

  /// Whether the row has rows under it that can be collapsed.
  final bool hasChildren;

  /// Whether those rows are hidden.
  final bool collapsed;

  /// The names of the projects above it, such as `Work › Website`.
  final String path;

  /// The name of its parent theme, or null when it has none.
  final String? themeName;
}

/// Shown when the search finds nothing.
class NoMatchItem extends TreeItem {
  /// Creates the row.
  const NoMatchItem(this.query);

  /// The search text.
  final String query;
}

/// The rows for [c]. [query] filters by name and path. A search opens every
/// group and branch that holds a match. [collapsedNodes] holds the ids of
/// the collapsed projects, [collapsedGroups] the collapsed groups.
List<TreeItem> buildTreeItems(
  Classification c, {
  String query = '',
  Set<String> collapsedNodes = const {},
  Set<GroupKind> collapsedGroups = const {},
}) {
  final q = query.trim().toLowerCase();
  final searching = q.isNotEmpty;
  final out = <TreeItem>[];
  for (final conn in c.connections) {
    final byId = {for (final p in conn.projects) p.id: p};

    List<ClassifiedProject> ancestors(ClassifiedProject p) {
      final seen = <String>{p.id};
      final list = <ClassifiedProject>[];
      var parent = byId[p.parentId];
      while (parent != null && seen.add(parent.id)) {
        list.add(parent);
        parent = byId[parent.parentId];
      }
      return list;
    }

    String pathOf(ClassifiedProject p) =>
        ancestors(p).reversed.map((a) => a.name).join(' › ');

    bool matches(ClassifiedProject p) =>
        !searching ||
        p.name.toLowerCase().contains(q) ||
        pathOf(p).toLowerCase().contains(q);

    GroupKind groupOf(ClassifiedProject p) {
      if (p.orphaned != null) return GroupKind.orphaned;
      return switch (p.label) {
        null => GroupKind.unsorted,
        ProjectLabel.theme => GroupKind.themes,
        ProjectLabel.milestone => p.parentThemeId == null
            ? GroupKind.noThemeMilestones
            : GroupKind.themes,
        ProjectLabel.maintenance => GroupKind.routines,
        ProjectLabel.ignored => GroupKind.ignored,
      };
    }

    final groups = {for (final k in GroupKind.values) k: <ClassifiedProject>[]};
    for (final p in conn.projects) {
      groups[groupOf(p)]!.add(p);
    }

    final rows = <TreeItem>[];
    for (final kind in GroupKind.values) {
      final members = groups[kind]!;
      if (members.isEmpty) continue;
      final List<TreeItem> body;
      if (kind == GroupKind.themes ||
          kind == GroupKind.unsorted ||
          kind == GroupKind.noThemeMilestones) {
        body = _treeRows(kind, members, conn, byId, ancestors, pathOf, matches,
            q, collapsedNodes: collapsedNodes);
      } else {
        body = [
          for (final p in members)
            if (matches(p))
              ProjectItem(
                  project: p,
                  connection: conn,
                  group: kind,
                  path: pathOf(p),
                  themeName: byId[p.parentThemeId]?.name),
        ];
      }
      if (body.isEmpty) continue;
      final collapsed = !searching && collapsedGroups.contains(kind);
      // Themes count themselves; their milestones are listed inside.
      final count = kind == GroupKind.themes
          ? members.where((p) => p.label == ProjectLabel.theme).length
          : members.length;
      rows.add(GroupItem(kind, count, collapsed: collapsed));
      if (!collapsed) rows.addAll(body);
    }
    if (rows.isNotEmpty && c.connections.length > 1) {
      out.add(ConnectionItem(conn.name));
    }
    out.addAll(rows);
  }
  if (searching && out.isEmpty) out.add(NoMatchItem(query.trim()));
  return out;
}

/// The rows of a group shown as a tree: children sit under their nearest
/// ancestor in the same group, parent first.
List<TreeItem> _treeRows(
  GroupKind kind,
  List<ClassifiedProject> members,
  ConnectionProjects conn,
  Map<String, ClassifiedProject> byId,
  List<ClassifiedProject> Function(ClassifiedProject) ancestors,
  String Function(ClassifiedProject) pathOf,
  bool Function(ClassifiedProject) matches,
  String q, {
  required Set<String> collapsedNodes,
}) {
  final ids = {for (final m in members) m.id};
  // A row sits under its nearest ancestor that is in this group.
  String? displayParent(ClassifiedProject p) {
    for (final a in ancestors(p)) {
      if (ids.contains(a.id)) return a.id;
    }
    return null;
  }

  final parentOf = {for (final m in members) m.id: displayParent(m)};
  final children = <String?, List<ClassifiedProject>>{};
  for (final m in members) {
    children.putIfAbsent(parentOf[m.id], () => []).add(m);
  }
  final searching = q.isNotEmpty;
  final visible = <String>{};
  if (searching) {
    for (final m in members.where(matches)) {
      String? id = m.id;
      while (id != null && visible.add(id)) {
        id = parentOf[id];
      }
    }
  }
  final out = <TreeItem>[];
  void walk(ClassifiedProject p, int depth) {
    if (searching && !visible.contains(p.id)) return;
    final kids = [
      for (final k in children[p.id] ?? const <ClassifiedProject>[])
        if (!searching || visible.contains(k.id)) k,
    ];
    final collapsed = !searching && collapsedNodes.contains(p.id);
    out.add(ProjectItem(
      project: p,
      connection: conn,
      group: kind,
      depth: depth,
      // A row under its parent in the group needs no path; a top row shows
      // the parent that lives in another group.
      path: depth == 0 && kind != GroupKind.themes ? pathOf(p) : '',
      hasChildren: kids.isNotEmpty,
      collapsed: collapsed,
      themeName: byId[p.parentThemeId]?.name,
    ));
    if (collapsed) return;
    for (final k in kids) {
      walk(k, depth + 1);
    }
  }

  for (final root in children[null] ?? const <ClassifiedProject>[]) {
    walk(root, 0);
  }
  return out;
}

/// Ids of every project that has rows under it in the theme tree, so that
/// "Collapse all" knows what to fold.
Set<String> collapsibleIds(Classification c) {
  final out = <String>{};
  for (final item in buildTreeItems(c)) {
    if (item is ProjectItem && item.hasChildren) out.add(item.project.id);
  }
  return out;
}
