"""The pure rules of project classification (spec 003): proposal, effective label, themes."""

from tefteri.domain.classification import (
    ProjectNode,
    effective_label,
    is_eligible,
    is_weekly_eligible,
    label_of,
    parent_theme,
    proposal_of,
    propose,
)
from tefteri.domain.enums import ProjectLabel

T, M, R, X = (
    ProjectLabel.THEME,
    ProjectLabel.MILESTONE,
    ProjectLabel.MAINTENANCE,
    ProjectLabel.IGNORED,
)


def nodes(*items: ProjectNode) -> dict[str, ProjectNode]:
    return {n.key: n for n in items}


# -- proposal (FR-004) -----------------------------------------------------------------------


def test_a_top_level_project_is_proposed_as_theme() -> None:
    proposal = propose(depth=0)
    assert (proposal.label, proposal.reason) == (T, "top_level")


def test_a_deeper_project_is_proposed_as_milestone() -> None:
    for depth in (1, 2, 5):
        proposal = propose(depth=depth)
        assert (proposal.label, proposal.reason) == (M, "nested")


def test_a_project_of_a_past_plan_is_proposed_as_milestone_even_at_top_level() -> None:
    proposal = propose(depth=0, was_committed=True)
    assert (proposal.label, proposal.reason) == (M, "was_committed")
    assert propose(depth=2, was_committed=True).reason == "was_committed"


def test_a_proposal_is_never_maintenance_or_ignored() -> None:
    for depth in range(4):
        for committed in (False, True):
            assert propose(depth, committed).label in (T, M)


# -- effective label, eligible, weekly-eligible (FR-007, FR-008) -------------------------------


def test_the_effective_label_is_the_stored_label_or_else_the_proposal() -> None:
    assert effective_label(R, propose(0)) == R
    assert effective_label(None, propose(0)) == T
    assert effective_label(None, propose(1)) == M


def test_an_unclassified_project_counts_as_its_proposal() -> None:
    tree = nodes(ProjectNode("a", None, None), ProjectNode("b", "a", None))
    assert is_eligible(tree, "a") and is_weekly_eligible(tree, "a")
    assert is_eligible(tree, "b") and is_weekly_eligible(tree, "b")


def test_an_ignored_project_and_its_descendants_are_not_eligible() -> None:
    tree = nodes(
        ProjectNode("a", None, X),
        ProjectNode("b", "a", M),
        ProjectNode("c", "b", None),
        ProjectNode("d", None, T),
    )
    assert not is_eligible(tree, "a")
    assert not is_eligible(tree, "b")
    assert not is_eligible(tree, "c")
    assert is_eligible(tree, "d")


def test_an_orphaned_project_is_not_eligible() -> None:
    tree = nodes(ProjectNode("a", None, T, orphaned=True))
    assert not is_eligible(tree, "a") and not is_weekly_eligible(tree, "a")


def test_a_maintenance_project_is_eligible_but_not_weekly_eligible() -> None:
    tree = nodes(ProjectNode("a", None, R), ProjectNode("b", "a", M))
    assert is_eligible(tree, "a") and not is_weekly_eligible(tree, "a")
    # Work inside a routine project is routine work, whatever its own label says.
    assert not is_weekly_eligible(tree, "b")
    assert is_eligible(tree, "b")


def test_an_unclassified_project_inside_a_routine_is_proposed_as_routine() -> None:
    tree = nodes(
        ProjectNode("a", None, R), ProjectNode("b", "a", None), ProjectNode("c", "b", None)
    )
    for key in ("b", "c"):
        proposal = proposal_of(tree, key)
        assert (proposal.label, proposal.reason) == (R, "inside_routine")
        assert not is_weekly_eligible(tree, key)
    # The user can still choose another label for it.
    tree = nodes(ProjectNode("a", None, R), ProjectNode("b", "a", T))
    assert label_of(tree, "b") == T


def test_a_loop_in_the_parent_links_does_not_make_the_routine_rule_loop() -> None:
    tree = nodes(ProjectNode("a", "b", None), ProjectNode("b", "a", None))
    assert proposal_of(tree, "a").label in (T, M)
    assert is_weekly_eligible(tree, "a")


def test_an_ignored_project_is_not_weekly_eligible() -> None:
    tree = nodes(ProjectNode("a", None, X))
    assert not is_weekly_eligible(tree, "a")


# -- parent theme (FR-021) ---------------------------------------------------------------------


def test_the_parent_theme_is_the_nearest_ancestor_that_is_a_theme() -> None:
    tree = nodes(
        ProjectNode("t1", None, T),
        ProjectNode("t2", "t1", T),
        ProjectNode("m", "t2", M),
        ProjectNode("n", "m", None),
    )
    assert parent_theme(tree, "n") == "t2"
    assert parent_theme(tree, "m") == "t2"
    assert parent_theme(tree, "t2") == "t1"


def test_a_project_with_no_theme_above_it_has_no_parent_theme() -> None:
    tree = nodes(ProjectNode("r", None, R), ProjectNode("m", "r", M))
    assert parent_theme(tree, "m") is None
    assert parent_theme(tree, "r") is None


def test_an_unclassified_top_level_project_is_a_theme_for_its_children() -> None:
    tree = nodes(ProjectNode("a", None, None), ProjectNode("b", "a", None))
    assert parent_theme(tree, "b") == "a"


def test_a_milestone_under_a_milestone_keeps_the_theme_above() -> None:
    tree = nodes(ProjectNode("t", None, T), ProjectNode("m1", "t", M), ProjectNode("m2", "m1", M))
    assert parent_theme(tree, "m2") == "t"


def test_a_cycle_in_the_parent_links_does_not_loop() -> None:
    tree = nodes(ProjectNode("a", "b", None), ProjectNode("b", "a", None))
    assert parent_theme(tree, "a") is None
    assert isinstance(is_eligible(tree, "a"), bool)
    assert propose(0).label in (T, M)


def test_a_parent_that_is_not_known_makes_the_project_top_level() -> None:
    tree = nodes(ProjectNode("a", "gone", None))
    assert parent_theme(tree, "a") is None
    assert is_eligible(tree, "a")
