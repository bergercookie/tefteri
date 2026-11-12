"""ORM models. Import every model here so metadata is complete."""

from tefteri.db.models.calendar_entry import CalendarEntry
from tefteri.db.models.checklist import ChecklistProgress
from tefteri.db.models.connection import Connection, SourceContainer
from tefteri.db.models.goal import Goal, Plan
from tefteri.db.models.links import TaskNoteLink
from tefteri.db.models.milestone import Milestone, MilestoneClosure, MilestoneRollover
from tefteri.db.models.note import Note
from tefteri.db.models.project_label import ProjectLabel, ProjectLabelHistory
from tefteri.db.models.review import PeriodReview
from tefteri.db.models.sync import Conflict, SyncRun
from tefteri.db.models.task import Task
from tefteri.db.models.task_category import TaskCategory
from tefteri.db.models.user import AuthSession, User
from tefteri.db.models.weekly import WeeklyPlan, WeeklyPlanProject

__all__ = [
    "AuthSession",
    "CalendarEntry",
    "ChecklistProgress",
    "Conflict",
    "Connection",
    "Goal",
    "Milestone",
    "MilestoneClosure",
    "MilestoneRollover",
    "Note",
    "PeriodReview",
    "Plan",
    "ProjectLabel",
    "ProjectLabelHistory",
    "SourceContainer",
    "SyncRun",
    "TaskCategory",
    "TaskNoteLink",
    "Task",
    "User",
    "WeeklyPlan",
    "WeeklyPlanProject",
]
