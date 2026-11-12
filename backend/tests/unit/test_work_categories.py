"""The pure rules of work categories (spec 005): categorize, label_on, percentages, counts."""

import random
from datetime import UTC, datetime, timedelta
from itertools import product

import pytest

from tefteri.domain.enums import CategoryReason, ProjectLabel, WorkCategory
from tefteri.domain.work_categories import (
    CategoryCounts,
    LabelEntry,
    ProjectContext,
    categorize,
    label_on,
    percentages,
)

M, T, MAINT, IGN = (
    ProjectLabel.MILESTONE,
    ProjectLabel.THEME,
    ProjectLabel.MAINTENANCE,
    ProjectLabel.IGNORED,
)
ALLOWED = {
    (WorkCategory.GOAL_ALIGNED, CategoryReason.COMMITTED_MILESTONE, False),
    (WorkCategory.MAINTENANCE, CategoryReason.MAINTENANCE_LABEL, False),
    (WorkCategory.MAINTENANCE, CategoryReason.INSIDE_ROUTINE, False),
    (WorkCategory.OFF_PLAN, CategoryReason.MILESTONE_NOT_COMMITTED, False),
    (WorkCategory.OFF_PLAN, CategoryReason.THEME, False),
    (WorkCategory.OFF_PLAN, CategoryReason.UNCLASSIFIED, True),
    (WorkCategory.OFF_PLAN, CategoryReason.NO_PROJECT, True),
    (WorkCategory.HIDDEN, CategoryReason.IGNORED, False),
    (WorkCategory.HIDDEN, CategoryReason.IGNORED_ANCESTOR, False),
}


def ctx(own: ProjectLabel | None, *ancestors: ProjectLabel | None) -> ProjectContext:
    return ProjectContext(True, own, ancestors)


def test_a_committed_milestone_is_goal_aligned() -> None:
    d = categorize(ctx(M), committed=True)
    assert (d.category, d.reason, d.unsorted) == (
        WorkCategory.GOAL_ALIGNED,
        CategoryReason.COMMITTED_MILESTONE,
        False,
    )


@pytest.mark.parametrize("committed", [True, False])
def test_a_maintenance_project_is_maintenance_committed_or_not(committed: bool) -> None:
    d = categorize(ctx(MAINT), committed)
    assert (d.category, d.reason) == (WorkCategory.MAINTENANCE, CategoryReason.MAINTENANCE_LABEL)


def test_a_milestone_that_is_not_committed_is_off_plan() -> None:
    d = categorize(ctx(M), committed=False)
    assert (d.category, d.reason) == (WorkCategory.OFF_PLAN, CategoryReason.MILESTONE_NOT_COMMITTED)


@pytest.mark.parametrize("committed", [True, False])
def test_a_theme_is_off_plan_even_when_its_id_is_committed(committed: bool) -> None:
    d = categorize(ctx(T), committed)
    assert (d.category, d.reason, d.unsorted) == (
        WorkCategory.OFF_PLAN,
        CategoryReason.THEME,
        False,
    )


def test_every_result_is_a_row_of_the_data_model() -> None:
    labels = [None, T, M, MAINT, IGN]
    seen = set()
    for own, a1, a2, committed in product(labels, labels, labels, [True, False]):
        d = categorize(ctx(own, a1, a2), committed)
        seen.add((d.category, d.reason, d.unsorted))
    d = categorize(ProjectContext(False), False)
    seen.add((d.category, d.reason, d.unsorted))
    assert seen == ALLOWED


def test_no_label_is_unsorted_and_no_project_is_unsorted() -> None:
    d = categorize(ctx(None), False)
    assert (d.category, d.reason, d.unsorted) == (
        WorkCategory.OFF_PLAN,
        CategoryReason.UNCLASSIFIED,
        True,
    )
    d = categorize(ProjectContext(False), False)
    assert (d.category, d.reason, d.unsorted) == (
        WorkCategory.OFF_PLAN,
        CategoryReason.NO_PROJECT,
        True,
    )


def test_an_ignored_project_or_ancestor_is_hidden() -> None:
    assert categorize(ctx(IGN), True).reason is CategoryReason.IGNORED
    d = categorize(ctx(M, None, IGN), True)
    assert (d.category, d.reason) == (WorkCategory.HIDDEN, CategoryReason.IGNORED_ANCESTOR)


@pytest.mark.parametrize("own", [T, M, None, MAINT])
@pytest.mark.parametrize("committed", [True, False])
def test_a_maintenance_ancestor_makes_the_task_maintenance(
    own: ProjectLabel | None, committed: bool
) -> None:
    d = categorize(ctx(own, T, MAINT), committed)
    assert d.category is WorkCategory.MAINTENANCE
    assert d.reason is (
        CategoryReason.MAINTENANCE_LABEL if own is MAINT else CategoryReason.INSIDE_ROUTINE
    )
    assert d.unsorted is False  # also for an unclassified own label


def test_an_ignored_ancestor_beats_a_maintenance_ancestor() -> None:
    assert categorize(ctx(T, MAINT, IGN), False).category is WorkCategory.HIDDEN
    assert categorize(ctx(T, IGN, MAINT), False).category is WorkCategory.HIDDEN
    assert categorize(ctx(MAINT, IGN), False).category is WorkCategory.HIDDEN


# -- label_on ---------------------------------------------------------------------------------

D0 = datetime(2026, 11, 1, tzinfo=UTC)
END = datetime(2026, 11, 10, 23, 59, 59, tzinfo=UTC)


def test_the_latest_entry_not_after_the_end_of_the_day_wins() -> None:
    entries = [
        LabelEntry(T, D0),
        LabelEntry(M, D0 + timedelta(days=3)),
        LabelEntry(MAINT, D0 + timedelta(days=30)),
    ]
    assert label_on(entries, END) is M


def test_an_entry_that_starts_later_is_ignored() -> None:
    assert label_on([LabelEntry(T, D0), LabelEntry(M, END + timedelta(seconds=1))], END) is T


def test_the_oldest_entry_is_used_when_every_entry_starts_later() -> None:
    later = END + timedelta(days=5)
    entries = [LabelEntry(M, later + timedelta(days=2)), LabelEntry(T, later)]
    assert label_on(entries, END) is T


def test_an_entry_with_no_label_means_unclassified() -> None:
    assert label_on([LabelEntry(T, D0), LabelEntry(None, D0 + timedelta(days=1))], END) is None


def test_no_entries_means_unclassified() -> None:
    assert label_on([], END) is None


def test_two_entries_with_the_same_start_take_the_last_in_the_given_order() -> None:
    assert label_on([LabelEntry(T, D0), LabelEntry(M, D0)], END) is M
    assert label_on([LabelEntry(M, D0), LabelEntry(T, D0)], END) is T


def test_naive_times_are_read_as_utc() -> None:
    naive = datetime(2026, 11, 1)
    assert label_on([LabelEntry(M, naive)], END) is M


# -- percentages ------------------------------------------------------------------------------


def test_percentages_of_round_numbers_stay() -> None:
    assert percentages(CategoryCounts(60, 25, 15)) == (60, 25, 15)


def test_a_tie_goes_to_goal_aligned_then_maintenance() -> None:
    assert percentages(CategoryCounts(1, 1, 1)) == (34, 33, 33)


def test_one_task_in_a_hundred_stays_one_percent() -> None:
    assert percentages(CategoryCounts(1, 0, 99)) == (1, 0, 99)


def test_percentages_add_up_to_100_for_random_counts() -> None:
    rng = random.Random(5)
    for _ in range(500):
        counts = CategoryCounts(rng.randint(0, 400), rng.randint(0, 400), rng.randint(0, 400))
        if counts.total == 0:
            continue
        p = percentages(counts)
        assert sum(p) == 100
        assert all(0 <= x <= 100 for x in p)
        for value, c in zip(
            p, (counts.goal_aligned, counts.maintenance, counts.off_plan), strict=True
        ):
            assert abs(value - 100 * c / counts.total) < 1  # never off by a whole point
            assert (c == 0) == (value == 0) or c * 100 < counts.total


def test_a_total_of_zero_gives_zeros_and_hidden_never_enters() -> None:
    assert percentages(CategoryCounts()) == (0, 0, 0)
    assert percentages(CategoryCounts(0, 0, 0, hidden=50)) == (0, 0, 0)
    assert percentages(CategoryCounts(1, 1, 0, hidden=1000)) == (50, 50, 0)


# -- CategoryCounts ---------------------------------------------------------------------------


def test_total_is_the_sum_of_the_three_and_excludes_hidden() -> None:
    c = CategoryCounts(1, 2, 3, 4)
    assert c.total == 6 and c.hidden == 4


def test_adding_is_field_by_field_and_associative() -> None:
    a, b, c = CategoryCounts(1, 2, 3, 4), CategoryCounts(5, 6, 7, 8), CategoryCounts(0, 1, 0, 1)
    assert a + b == CategoryCounts(6, 8, 10, 12)
    assert (a + b) + c == a + (b + c)


def test_the_sum_of_31_days_equals_the_count_in_one_pass() -> None:
    rng = random.Random(9)
    cats = [WorkCategory.GOAL_ALIGNED, WorkCategory.MAINTENANCE, WorkCategory.OFF_PLAN]
    cats.append(WorkCategory.HIDDEN)
    days = [[rng.choice(cats) for _ in range(rng.randint(0, 9))] for _ in range(31)]
    total = CategoryCounts()
    for day in days:
        counts = CategoryCounts()
        for cat in day:
            counts += CategoryCounts.one(cat)
        total += counts
    flat = CategoryCounts()
    for cat in (c for day in days for c in day):
        flat += CategoryCounts.one(cat)
    assert total == flat
