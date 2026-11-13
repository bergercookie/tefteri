"""Enumerations shared across the domain, persistence and API layers."""

from enum import StrEnum


class ConnectionKind(StrEnum):
    """Kind of external application a connection talks to."""

    TASKS = "tasks"
    CALENDAR = "calendar"
    NOTES = "notes"


class ConnectionStatus(StrEnum):
    """Health of a connection."""

    OK = "ok"
    NEEDS_ATTENTION = "needs_attention"
    ERROR = "error"


class SyncState(StrEnum):
    """Synchronisation state of a cached item."""

    SYNCED = "synced"
    CONFLICT = "conflict"
    DELETED_REMOTELY = "deleted_remotely"


class Resolution(StrEnum):
    """How the user resolved a conflict."""

    KEEP_LOCAL = "keep_local"
    KEEP_REMOTE = "keep_remote"


class Capability(StrEnum):
    """Optional features an adapter may support."""

    TASK_TIME = "task_time"
    RECURRING = "recurring"
    NOTE_APPEND = "note_append"
    SUBPROJECTS = "subprojects"
    ARCHIVE_PROJECTS = "archive_projects"
    TASK_REMINDERS = "task_reminders"
    RENAME_PROJECTS = "rename_projects"
    RESTORE_PROJECTS = "restore_projects"
    PROJECT_TREE = "project_tree"
    STABLE_PROJECT_IDS = "stable_project_ids"
    CREATE_TASKS = "create_tasks"
    COMPLETION_TIMES = "completion_times"
    MOVE_TASKS = "move_tasks"


class ProjectLabel(StrEnum):
    """What a project is for the user. The label lives only in tefteri (spec 003)."""

    THEME = "theme"
    MILESTONE = "milestone"
    MAINTENANCE = "maintenance"
    IGNORED = "ignored"


class OrphanReason(StrEnum):
    """Why a project that tefteri knows is no longer in the task app."""

    MISSING = "missing"
    ARCHIVED = "archived"


class MilestoneState(StrEnum):
    """Where a milestone project stands (spec 004)."""

    ACTIVE = "active"
    PARKED = "parked"
    CLOSED = "closed"
    DONE = "done"


class ReviewDecision(StrEnum):
    """What the weekly review decides for an unfinished milestone (spec 004)."""

    RECOMMIT = "recommit"
    PARK = "park"
    CLOSE = "close"
    DECIDE_LATER = "decide_later"


class WorkCategory(StrEnum):
    """The category of a completed task (spec 005).

    ``goal_aligned``, ``maintenance`` and ``off_plan`` are the three work categories. ``hidden``
    is not a work category: it is the count of tasks in ignored projects, which no statistic
    includes in its total (FR-008).
    """

    GOAL_ALIGNED = "goal_aligned"
    MAINTENANCE = "maintenance"
    OFF_PLAN = "off_plan"
    HIDDEN = "hidden"


class GoalState(StrEnum):
    """The state of an annual goal (spec 006). ``done`` is a legacy state kept for history."""

    ACTIVE = "active"
    RETIRED = "retired"


class UpdateSource(StrEnum):
    """Who keeps a key result's values up to date (spec 006, FR-004)."""

    MANUAL = "manual"
    AUTOMATIC = "automatic"


class ValueSource(StrEnum):
    """Where a stored value of a key result came from (spec 006, FR-009)."""

    MANUAL = "manual"
    AUTOMATIC = "automatic"


class PlanChangeKind(StrEnum):
    """What a row of ``plan_changes`` records (spec 006, data-model.md)."""

    GOAL_CREATED = "goal_created"
    GOAL_EDITED = "goal_edited"
    GOAL_RETIRED = "goal_retired"
    GOAL_RESTORED = "goal_restored"
    KEY_RESULT_CREATED = "key_result_created"
    KEY_RESULT_EDITED = "key_result_edited"
    KEY_RESULT_RETIRED = "key_result_retired"
    KEY_RESULT_RESTORED = "key_result_restored"
    LINK_ADDED = "link_added"
    LINK_REMOVED = "link_removed"
    MIGRATED = "migrated"


class LinkEndReason(StrEnum):
    """Why a link between a key result and a theme project ended (spec 006, FR-013)."""

    REMOVED = "removed"
    RELINKED = "relinked"
    KEY_RESULT_RETIRED = "key_result_retired"
    GOAL_RETIRED = "goal_retired"


class ChangeSource(StrEnum):
    """Where a plan change or a link change came from (spec 006)."""

    USER = "user"
    UNDO = "undo"
    SEED = "seed"
    MIGRATION = "migration"


class YearState(StrEnum):
    """Where a planning year stands relative to today (spec 006, FR-033)."""

    PAST = "past"
    CURRENT = "current"
    FUTURE = "future"


class CategoryReason(StrEnum):
    """Why a completed task got its category (spec 005, data-model.md)."""

    COMMITTED_MILESTONE = "committed_milestone"
    MAINTENANCE_LABEL = "maintenance_label"
    INSIDE_ROUTINE = "inside_routine"
    MILESTONE_NOT_COMMITTED = "milestone_not_committed"
    THEME = "theme"
    UNCLASSIFIED = "unclassified"
    NO_PROJECT = "no_project"
    IGNORED = "ignored"
    IGNORED_ANCESTOR = "ignored_ancestor"


class FocusEntryStatus(StrEnum):
    """Whether a theme entry is still in a month's focus or has left it."""

    IN_FOCUS = "in_focus"
    SWAPPED_OUT = "swapped_out"
    REMOVED = "removed"


class FocusChangeKind(StrEnum):
    """The kind of one logged change to a monthly focus."""

    SWAP = "swap"
    ADD = "add"
    REMOVE = "remove"
    TARGET = "target"


class FocusChangeSource(StrEnum):
    """Whether a focus-change log row is a user action or its undo."""

    USER = "user"
    UNDO = "undo"


class ThemeDecision(StrEnum):
    """The month-end decision for a theme."""

    CARRY = "carry"
    DROP = "drop"
    REPLACE = "replace"
    LATER = "later"


class ThemeSuggestionReason(StrEnum):
    """Why a saved review suggests a theme for the next month."""

    CARRY = "carry"
    REPLACE = "replace"


class SkippedSuggestionReason(StrEnum):
    """Why a previous theme cannot be suggested again."""

    ORPHANED = "orphaned"
    RELABELLED = "relabelled"
    IGNORED = "ignored"


class TargetMarker(StrEnum):
    """The result of comparing milestone completions with a target."""

    MET = "met"
    MISSED = "missed"
    BEATEN = "beaten"
    NO_TARGET = "no_target"


class KeyResultUpdate(StrEnum):
    """Whether a key result has a value dated inside the month."""

    UPDATED = "updated"
    NOT_UPDATED = "not_updated"


class MonthlyFlagCode(StrEnum):
    """Key-result and goal flags shown in the monthly planning and review views."""

    NO_KEY_RESULT = "no_key_result"
    NO_USABLE_THEME = "no_usable_theme"
    OVERDUE = "overdue"
    NO_THEME_IN_FOCUS = "no_theme_in_focus"
    PAST_DEADLINE = "past_deadline"


class TrendState(StrEnum):
    """The comparison of a month's off-plan share with the two prior months."""

    RISING = "rising"
    NOT_RISING = "not_rising"
    NOT_ENOUGH_HISTORY = "not_enough_history"


class CountNote(StrEnum):
    """Non-blocking guidance for the number of themes in a monthly focus."""

    EMPTY = "empty"
    BELOW = "below"
    ABOVE = "above"


class MonthState(StrEnum):
    """A month relative to the user's local today."""

    PAST = "past"
    CURRENT = "current"
    FUTURE = "future"


class KeyResultOutcome(StrEnum):
    """The final result of one key result in an annual review."""

    HIT = "hit"
    MISSED = "missed"
    NO_VALUE = "no_value"
    RETIRED = "retired"
    IN_PROGRESS = "in_progress"


class DeadlineState(StrEnum):
    """Whether a key result reached its target by its deadline."""

    REACHED = "reached"
    NOT_REACHED = "not_reached"
    OPEN = "open"
    NO_VALUE = "no_value"


class MonthStatus(StrEnum):
    """The presence of a monthly review snapshot for one month of the year."""

    STORED = "stored"
    MISSING = "missing"
    OPEN = "open"
    FUTURE = "future"


class ThemeHint(StrEnum):
    """A neutral comparison of milestone work and key result movement."""

    MUCH_SHIPPED_LITTLE_MOVEMENT = "much_shipped_little_movement"
    MOVEMENT_NOT_FROM_THEME = "movement_not_from_theme"


class ReviewEmptyReason(StrEnum):
    """Why an annual review has no data to show."""

    NO_SNAPSHOTS = "no_snapshots"
    NO_GOALS = "no_goals"
    FUTURE_YEAR = "future_year"
