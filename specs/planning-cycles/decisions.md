# Decisions for the planning and review cycles

Date: 2026-11-11. Author of the decisions: the project owner.

## Decided

1. **Cycles and their unit of work.**
   - Annual planning works on goals and key results.
   - Monthly planning works on theme projects.
   - Weekly planning works on milestone projects.
   - Goals exist only at the annual level. Month and week goals leave the planning flow.
     Existing month and week goal rows stay as read-only history.
2. **Weekly cap.** The cap of three counts milestone projects. Going over the cap is allowed
   and shows a warning. The server no longer rejects a fourth project.
3. **Evolve, do not rebuild.** The weekly planning flow that exists today (`WeeklyPlan`,
   `WeeklyPlanProject`, look-back) is changed in place.
4. **Scope.** All six features are specified now. Implementation starts with 003.
5. **Words.** The product keeps its current words (project, committed plan, look-back,
   parked, done outside the plan). It adds theme, milestone and maintenance.
6. **Out of scope for these six features.** Calendar integration in planning, quarterly
   checkpoints, paired controllable key results, and the flat-mapping fallback for task
   managers without nested projects.

## Defaults accepted (confirm during clarify)

- Key results have one type: a number with a start value, a target and a deadline. The
  source is manual or automatic. Yes/no and count types come later.
- A milestone is done when all its open tasks are closed or dropped, or when the user marks
  it done. Dropped tasks never block completion.
- Swapping a theme mid-month and retiring or re-linking a goal mid-year are allowed. They
  are recorded in history and never change stored snapshots.

## Branches

The cloud session develops on one branch. Spec directories are numbered per feature, and
all of them are committed on that branch until the project owner says otherwise.

## Shared glossary (every spec MUST use these terms and names)

- **Theme project**: a project labelled theme (feature 003). A long-running home for related work. Never committed to a week.
- **Milestone project**: a project labelled milestone. A small sub-project under a theme with a clear done-state, finishable in one week. The unit of weekly commitment (feature 004). Holds state (active, parked, closed, done), rollover count and an expected-rollover marker.
- **Maintenance project** and **ignored project**: labels from feature 003. Maintenance is outside the weekly cap and outside milestone rules.
- **Goal**: annual only. One loose sentence, with one to three key results.
- **Key result**: a measurable success criterion of a goal (feature 006): metric, start value, target, deadline, current value, update source (manual or automatic).
- **Key result to theme link**: many-to-many, per annual cycle, kept as history (feature 006).
- **Monthly focus**: the theme projects chosen for a month, each with a milestone-count target (feature 007).
- **Weekly commitment**: the milestone projects and committed task ids of a week (feature 004). It evolves the existing `WeeklyPlan` and `WeeklyPlanProject`.
- **Work categories**: goal-aligned (in a committed milestone), maintenance (in a maintenance project), off-plan (goal-type work that was not committed). Feature 005.
- **Review snapshot**: the stored result of a monthly review (feature 007), read by the annual review (feature 008).
- **Orphaned**: a project that disappeared from the task manager. It keeps its label and history.
- Features 004 to 008 depend on the labels and on the capability check from 003. No spec may name a specific task manager outside its Assumptions section.
- Existing month and week `Goal` rows stay as read-only history. They are not shown in the new flows.
