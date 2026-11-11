"""The rules of project classification (spec 003). Pure functions: no database, no adapter.

A project has a *label* that only tefteri stores: ``theme``, ``milestone``, ``maintenance`` or
``ignored``. A project with no label is *unclassified* and counts as its *proposal*. Later
features (004 to 008) use these functions and do not restate the rules.

The functions that look at the tree take a mapping from a project key to a ``ProjectNode``. The
key is any stable string, for example the project id. A parent that is not in the mapping makes
the project top level. A cycle in the parent links is cut, so no function loops.
"""

from collections.abc import Mapping
from dataclasses import dataclass

from tefteri.domain.enums import ProjectLabel

_MAX_DEPTH = 64
"""No real tree is deeper. It also stops a loop in bad parent links."""


@dataclass(frozen=True)
class Proposal:
    """The label that tefteri suggests for an unclassified project, and why."""

    label: ProjectLabel
    reason: str  # 'top_level' | 'nested' | 'was_committed' | 'inside_routine'


@dataclass(frozen=True)
class ProjectNode:
    """What the rules need to know about one project."""

    key: str
    parent_key: str | None
    label: ProjectLabel | None
    was_committed: bool = False
    """The project is in a past weekly plan."""
    orphaned: bool = False
    """The project is no longer in the task app."""


def propose(depth: int, was_committed: bool = False) -> Proposal:
    """Propose a label. ``depth`` is 0 for a top-level project.

    A project that was in a past weekly plan is a milestone, even at top level. Otherwise a top
    level project is a theme and a deeper one is a milestone. ``propose`` never gives
    ``maintenance`` or ``ignored``: only the user decides that. A project inside a routine project
    is the one exception, and ``proposal_of`` handles it.
    """
    if was_committed:
        return Proposal(ProjectLabel.MILESTONE, "was_committed")
    if depth <= 0:
        return Proposal(ProjectLabel.THEME, "top_level")
    return Proposal(ProjectLabel.MILESTONE, "nested")


def effective_label(label: ProjectLabel | None, proposal: Proposal) -> ProjectLabel:
    """Return the stored label, or the proposal when the project is unclassified."""
    return label if label is not None else proposal.label


def _ancestors(nodes: Mapping[str, ProjectNode], key: str) -> list[ProjectNode]:
    """Return the ancestors of ``key``, nearest first. A cycle or an unknown parent ends it."""
    out: list[ProjectNode] = []
    seen = {key}
    parent_key = nodes[key].parent_key
    while parent_key is not None and parent_key in nodes and len(out) < _MAX_DEPTH:
        if parent_key in seen:
            break
        seen.add(parent_key)
        parent = nodes[parent_key]
        out.append(parent)
        parent_key = parent.parent_key
    return out


def depth_of(nodes: Mapping[str, ProjectNode], key: str) -> int:
    """Return how many ancestors a project has (0 for a top-level project)."""
    return len(_ancestors(nodes, key))


def _inside_routine(nodes: Mapping[str, ProjectNode], key: str) -> bool:
    """Return whether an ancestor has the stored label ``maintenance``.

    Only a stored label can start a routine: a proposal of ``maintenance`` itself comes from a
    stored one higher up the same chain. So this never needs the labels of the ancestors to be
    worked out, and a loop in the parent links cannot make it loop.
    """
    return any(a.label is ProjectLabel.MAINTENANCE for a in _ancestors(nodes, key))


def proposal_of(nodes: Mapping[str, ProjectNode], key: str) -> Proposal:
    """Return the proposal for one project of the tree.

    Work inside a routine project is routine work: an unclassified project that sits inside a
    project with the effective label ``maintenance`` is proposed as ``maintenance`` (reason
    ``inside_routine``). The user can still choose another label.
    """
    if _inside_routine(nodes, key):
        return Proposal(ProjectLabel.MAINTENANCE, "inside_routine")
    return propose(depth_of(nodes, key), nodes[key].was_committed)


def label_of(nodes: Mapping[str, ProjectNode], key: str) -> ProjectLabel:
    """Return the effective label of one project of the tree."""
    return effective_label(nodes[key].label, proposal_of(nodes, key))


def parent_theme(nodes: Mapping[str, ProjectNode], key: str) -> str | None:
    """Return the key of the nearest ancestor with the effective label theme (FR-021).

    ``None`` means that the project has no theme.
    """
    for ancestor in _ancestors(nodes, key):
        if label_of(nodes, ancestor.key) is ProjectLabel.THEME:
            return ancestor.key
    return None


def is_eligible(nodes: Mapping[str, ProjectNode], key: str) -> bool:
    """Return whether a planning picker may list the project (FR-007).

    It is not orphaned, not ignored and has no ignored ancestor. An unclassified project
    counts as its proposal, which is never ``ignored``.
    """
    node = nodes[key]
    if node.orphaned:
        return False
    if label_of(nodes, key) is ProjectLabel.IGNORED:
        return False
    return all(label_of(nodes, a.key) is not ProjectLabel.IGNORED for a in _ancestors(nodes, key))


def is_weekly_eligible(nodes: Mapping[str, ProjectNode], key: str) -> bool:
    """Return whether the weekly project picker lists the project (FR-008).

    It is eligible, its own label is not ``maintenance`` and it is not inside a ``maintenance``
    project: work inside a routine project is routine work, whatever its own label says.
    """
    if not is_eligible(nodes, key) or label_of(nodes, key) is ProjectLabel.MAINTENANCE:
        return False
    return not _inside_routine(nodes, key)
