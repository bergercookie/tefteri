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

## Cross-spec resolutions (from the analysis of 2026-11-11)

Each rule has ONE owner spec. The other specs reference it and do not restate it.

1. **Milestone completion data (owner 004).** A milestone stores a done date (the day its last task closed, or the day the user marked it done, never the review day) and the theme it had at that moment. 007 and 008 read these two fields. Automatic completion needs at least one closed task (not only dropped ones). A milestone with no tasks is never done automatically.
2. **Words (owner glossary).**
   - "Parked" is a milestone state set by the park decision. Tasks that were not picked are "not committed this week".
   - 004 calls a milestone under a theme that is not in the month's focus "outside focus". It is computed when read, from the monthly focus, never stored. "Off-plan" and "done outside the plan" mean only completed work that was not committed (owner 005).
   - Use "work categories" (not "kinds") and "planning year" (not "annual cycle").
   - "Parent theme" is the nearest ancestor labelled theme. If there is none, the milestone is shown as "no theme".
   - "Dropped task" means closed without completion.
3. **Weekly cap and review (owner 004).** A milestone is committed at most once per week. The cap warns and never rejects. The weekly review has a "decide later" choice on every unfinished milestone. It leaves the milestone unchanged and does not change its rollover count. The picker shows a reminder. The expected-rollover marker is stored per rollover event. The nudge appears after two consecutive unmarked rollovers. Close-and-return shows the number of tasks it moves, asks to confirm, and can be undone by reopening the milestone. The "served focus" share is the share of completed committed tasks under focus themes. The month of a week is the month of its Monday. 004 uses the weekly list from 005 and does not restate the 200-task cap.
4. **Labels (owner 003).** 003 stores a label history (project, label, from-date). Archiving from Tefteri is shown as orphaned with the reason "archived". One shared "create project and label it" rule: write to the task manager first, then record the label. 004 and 006 use it. Bulk relabel can be undone. A flat project list is refused (no edge case that accepts it). Other specs refer to "eligible per 003" for the picker rules.
5. **Work categories (owner 005).** The category of a task is stored when the task is first seen as completed and is never recomputed. Month totals are the sum of days and year totals are the sum of months. 005 needs 004 (no fallback). Snapshots and reviews store counts per category and a hidden count, never shares. Percentages are computed on display.
6. **Key results (owner 006).** A goal has up to three key results (at least one is recommended). A key result has a dated series of values. Both manual entry and an inbound push write to this series. The push has a named contract in the 006 plan: one token per user, key result id, value, time stamp. 007 reads the latest value and its time stamp and never pulls. The base of a month is the last series value on or before its first day. A past planning year allows value entry but not changes to structure. 006 owns the three flags: "no usable theme" (no linked theme, or all linked themes are orphaned or ignored); 007 adds "no theme in focus". 006 owns next-year seeding with a "from year N" input and the rule "unmet = last value did not reach the target". 008 links to it. 006 refers to old reviews as "stored period reviews". Snapshot rules belong to 007.
7. **Monthly cycle (owner 007).** A target left empty is stored as none. An explicit 0 is a real target. The review writes manual key result values into the 006 series. Snapshots are immutable and versioned on reopen. 008 reads the current version. A "no theme" entry appears in the outside-focus list. The words "swap" (mid-month) and "replace" (end of month decision) are different and both shown with a hint.
8. **Annual review (owner 008).** Totals and the proportion bar come from snapshots only. The drill-down is live and the screen says it may differ. A key result is "hit" when its last value in the year reached the target. The screen also shows "reached by deadline" as a second line. "Differ strongly" means: shipped milestones at or above the theme target while the key result moved less than 25% of its start-to-target span. The review writes only notes. There is no "marked final" control.
9. **Usability rules for every spec.** Every picker that can be empty offers an inline action ("label a project as theme" or "create a theme"). Every term is explained once, at first use. Every destructive choice shows its effect and can be undone. One owner per rule: orphans (003), goal removal from week and month flows (006), no time tracking (005).

10. **Work inside a routine (owner 003).** A project inside a project labelled maintenance is routine work. It is proposed as maintenance when unclassified, and it is never offered in the weekly picker. Feature 005 counts the tasks of such a project as the work category maintenance, whatever the label of the project itself is.
