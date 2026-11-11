# Tefteri: Planning and Review Specification

Nov 11, 2026 · @Nikos

## Status of this specification

*This specification comes only from one planning conversation. I have not read the full state of the Tefteri project (code, the `specs/` folder, `.specify`), so details may be inaccurate or clash with what already exists. Before splitting it into coding tasks, reconcile it with the existing specs and code, and treat conflicts as questions for the author, not as errors in the repo.

## Purpose and principles

Tefteri adds three nested planning cycles (annual, monthly, weekly), each closed by a review, on top of the user's existing task manager (Vikunja first), so that daily work visibly serves goals the user set in advance. It is for personal productivity first and works for professional work too.

Principles that every requirement below follows:

1. **The task manager is storage; Tefteri holds the opinions.** Projects and tasks live in the task manager. Goals, key results, project types and links live in Tefteri's own database.
2. **Measure completions, never time.** There is no time tracking anywhere. Progress is counted in milestones finished and tasks closed.
3. **Constraint over capture.** A small weekly cap forces trade-offs, and the weekly unit is a finishable outcome, not an open-ended area.
4. **Cascade by default, never by force.** Planning flows from goals to themes to milestones. Work outside the plan is allowed but visible.
5. **Honest statistics.** Goal work, maintenance work and off-plan work are always shown separately.
6. **Guess, then confirm.** Wherever possible the app proposes a classification or default and the user corrects it, instead of answering a questionnaire.

## Concepts and data model

Work rolls up through one chain: task, milestone project, theme project, key result, goal. Every concept below is either a task manager object that Tefteri labels, or a record that exists only in Tefteri.

| Concept | Lives in | Meaning | Tefteri-side data |
| --- | --- | --- | --- |
| Goal | Tefteri | A loose, one-sentence aim for the year, such as "get better at open source". | Annual cycle, text |
| Key result | Tefteri | A measurable success criterion set up front, such as "1,000 stars on one repo by December". One to three per goal. | Goal, metric, start value, target, deadline, current value, update source (manual or automatic) |
| Theme project | Task manager, labelled in Tefteri | A long-running project that acts as a home for related work. Never committed to a week directly. | External project ID, type = theme |
| Milestone project | Task manager, labelled in Tefteri | A small sub-project under a theme with a clear done-state, meant to be finished within one week. This is what gets committed weekly. | External project ID, parent theme, state (active, parked, closed, done), rollover count, expected-rollover marker |
| Maintenance project | Task manager, labelled in Tefteri | Standing routine work such as an admin project (groceries, chores). No finish line, no rollover, outside the weekly cap. | External project ID, type = maintenance |
| Ignored project | Task manager, labelled in Tefteri | Dormant or irrelevant projects hidden from planning. | External project ID, type = ignored |
| Task | Task manager | A granular unit of work inside a milestone or maintenance project. | None beyond the external task ID |
| Key result to theme link | Tefteri | Says which themes serve which key result. Many-to-many, made per annual cycle, kept as history. | Key result, theme, cycle |
| Monthly focus | Tefteri | The themes chosen for a month, each with a milestone-count target. | Month, theme, target |
| Weekly commitment | Tefteri | The milestone projects and the task list committed for a week. | Week, milestone projects, committed task IDs |
| Review snapshot | Tefteri | The stored result of a monthly review, so the annual review reads history instead of recomputing it. | Month, per-theme targets and results, key result values |

Classification of projects (theme, milestone, maintenance, ignored) is stored only in Tefteri and keyed on the task manager's project ID. Nothing is written to the task manager to record it.

## Task manager integration

Vikunja is the first supported task manager. Because Tefteri's authors decide which task managers are supported, the assumptions below are integration requirements that each connector declares and that are verified when the user connects, not hopes.

| Capability | Needed for | If missing |
| --- | --- | --- |
| Nested projects, at least two levels | Milestone projects under themes | Connector falls back to a flat mapping kept in Tefteri's database |
| Stable project IDs that survive rename and move | The classification mapping | Connector not supported |
| Read the full project tree and detect deleted or moved projects | Sync and reconciliation | Connector not supported |
| Create and archive projects | Weekly planning, closing a milestone | Connector not supported |
| Create tasks inside a project | Weekly planning | Connector not supported |
| Move tasks between projects | Close a milestone and return its tasks to the parent theme | Hide that option |
| Rename projects | Renaming from inside Tefteri | Hide that option |
| Task completion timestamps | Cadence and completion statistics | Connector not supported |

Sync rules:

- The mapping is keyed on project ID, never on name.
- Reconcile on every sync. A project that disappears from the task manager is marked orphaned, not deleted from Tefteri, and the app never crashes on it.
- A rename made in Tefteri writes to the task manager first and updates Tefteri's mapping only if that write succeeds, so the two never disagree.
- A rename made directly in the task manager is picked up as a new title on the next sync, with no effect on the mapping.
- Tefteri adds no labels, fields or tags to the user's task manager. Any visible hint, such as a naming convention, is optional and cosmetic, never the source of truth.

## Onboarding

Onboarding only identifies and labels the user's existing projects. It does not link themes to goals, because that happens in each annual planning session.

The app makes a guess for the user to review instead of asking a questionnaire. The default guess for Vikunja is that top-level projects are themes and everything below them is a milestone project. The depth rule is a default, never a constraint, because some deeper projects are really long-running sub-themes.

1. **Import and propose.** Read the project tree and show it with each project pre-labelled as theme or milestone. Signals such as depth, age and whether a project has children may refine the guess.
2. **Fix labels.** The user can relabel any project as theme, milestone, maintenance or ignored.
3. **Flag maintenance.** The user marks the admin project and any other routine or standing projects.
4. **Ignore the dormant.** Old or irrelevant projects are marked ignored so they never appear in planning pickers.
5. **Rename if wanted.** The user can rename projects here, and the rename is written through to the task manager (see integration rules).

Unclassified projects sit in an "unsorted" bucket. The app nudges the user to classify them gently and never blocks planning on them. Onboarding can be re-run, and new projects that appear later are proposed for classification on the next sync.

## Annual planning

Annual planning produces the year's goals, their success criteria, and the map from key results to theme projects, all fixed before the year starts but editable later.

1. **Write goals.** Each goal is a loose sentence. It does not need to be measurable by itself.
2. **Add key results.** Each goal gets one to three key results, each with a number and a deadline, so success criteria exist before any work begins. Example: goal "get better at open source", key result "reach 1,000 stars on one repository by December".
3. **Link key results to themes.** Every key result is linked to one or more theme projects. One theme may serve several key results, and one key result may be served by several themes.
4. **Create missing themes.** If no suitable theme exists, the user can create a new theme project from this screen.
5. **Flag gaps.** A key result with no linked theme is flagged on the planning screen, while it is still cheap to fix.

Requirements:

- Links belong to an annual cycle. Last year's links are kept as history, and a new cycle offers them as editable suggestions instead of a blank slate.
- Links and key results stay editable during the year, since some will turn out to be wrong.
- Onboarding never creates links. Only annual planning does.

## Monthly planning

Monthly planning is a light selection step: the user picks which theme projects get focus this month and sets a completion-based target for each. It does not create milestone projects, since those are invented during weekly planning.

1. **Pick themes.** The user chooses the themes to focus on, typically three to five.
2. **Set targets.** Each chosen theme gets a milestone-count target, such as "finish three milestones under the open source theme". No time budgets or hour targets.
3. **See what is behind each choice.** The screen shows each theme's linked key results and how far each has moved, so the choice is informed by progress.
4. **See what is unattended.** Any key result with no theme selected this month is flagged quietly as unattended, so ignoring it is a deliberate choice.

The selected themes and targets become the month's focus list, which weekly planning draws from.

## Weekly planning

Weekly planning commits a small set of self-contained milestone projects, each finishable by the end of the week, and assembles the task list for them. Long-running theme projects are never committed directly.

1. **Start from the monthly focus.** The picker shows the month's focus themes first, highlighted.
2. **Choose up to three milestone projects.** For each, the user either selects an existing milestone project (including parked ones) or creates a new one under a theme. A new milestone needs a clear done-state, such as "ship the login flow" rather than "work on auth".
3. **Pick tasks.** Tasks come from an interactive menu of the milestone's existing tasks, or the user adds new tasks under it.
4. **Allow off-plan choices.** A milestone under a theme that is not on the monthly list is allowed and tagged off-plan.
5. **Commit.** The assembled task list is committed. From then on the user executes, and the weekly review closes the cycle.

Requirements:

- The weekly cap is three. Whether it counts milestone projects or themes, and whether it is a hard limit or a warning, is an open question (see below).
- Maintenance projects never appear in the weekly picker and never count against the cap.
- Creating a milestone calls the task manager API to create a sub-project under the chosen theme, then records it in Tefteri as a milestone.

## Daily execution and maintenance work

A system that only knows goal work would misrepresent the week, so routine work is a first-class, separate kind of work. Maintenance projects, such as an admin project for groceries and daily routines, are real work that is not tied to any goal.

- Maintenance projects are exempt from milestone rules: no finish line, no rollover, no nagging, and no place in the weekly cap.
- Planning never asks the user to commit to maintenance tasks. They surface in daily execution alongside the committed milestone tasks.
- Every task completed during a week falls into one of three categories: goal-aligned (part of a committed milestone), maintenance (in a maintenance project), or off-plan (goal-type work that was not committed). The weekly page already shows tasks completed outside the commitment, and this spec extends that data to the monthly and annual views.

## Weekly review

The weekly review shows how the week went and forces a decision on every unfinished milestone before the next planning session.

**What it shows**

- Completion and cadence: committed tasks completed, milestones finished, pace across the week.
- The split of completed work into goal-aligned, maintenance and off-plan.
- How much of the work served the month's focus themes.

**Decision for each unfinished milestone**

1. **Keep and recommit.** It is still the right outcome and goes into next week's commitment.
2. **Keep but park.** It matters, but not next week. It stays active and appears in the picker later.
3. **Close and return its tasks to the parent theme.** The scope was wrong. The milestone is closed and its open tasks move to the parent theme project.

**Rollover tracking**

- Each recommit increases the milestone's rollover count.
- When recommitting, the user may mark it as an expected rollover ("this was bigger than a week"). Expected rollovers never trigger a nudge.
- A milestone recommitted twice without the expected marker triggers a nudge to re-scope it.
- A deliberate two-week milestone is simply a milestone recommitted once with the marker.

## Monthly review

The monthly review compares what was done with what moved, and it is where key results are updated.

1. **Targets vs results.** For each focus theme, show milestones completed against the month's target.
2. **Update key results.** Key results fed by an automatic source, such as GitHub stars, are pulled in. Manual ones get a quick prompt for a new value.
3. **Show the gap.** Put milestones shipped next to key result movement, so a result like "six shipped, stars barely moved" is visible.
4. **Show the off-plan trend.** Display the month's off-plan share and whether it is rising. A steady maintenance slice is normal. Growing off-plan goal work suggests the plan does not match reality.
5. **Decide for each theme.** Carry it forward, drop it, or swap it for another.
6. **Store a snapshot.** Save the month's targets, results and key result values for the annual review.

## Annual review

The annual review is the monthly review zoomed out: it reads the stored monthly snapshots and does not recompute history.

- For each goal, show whether each key result was hit, with the twelve monthly snapshots behind it.
- Show which themes served which key results, using that cycle's stored links, and whether the themes chosen were the right ones (milestones shipped against key result movement).
- Show the year's split between goal-aligned, maintenance and off-plan work.
- Seed the next annual planning session: offer this year's links and unmet key results as editable suggestions.

## Visual language and statistics

All weekly, monthly and annual views use one visual language so that the three kinds of work are always distinguishable and none is hidden.

| Kind of work | Styling | Weekly view | Monthly and annual views |
| --- | --- | --- | --- |
| Goal-aligned | Main style | Listed | Count, with drill-down |
| Maintenance | Muted | Listed | Count, with drill-down |
| Off-plan | Outlined or accented | Listed | Count, with drill-down |

At monthly and annual zoom, show counts and a single proportion bar (for example 60% goal work, 25% maintenance, 15% off-plan) instead of task lists, with drill-down for detail. The weekly page already shows completed tasks that were not committed, so this extends existing data and adds aggregation, not new modelling.

## Open questions and out of scope

These points were not settled in the conversation and need the author's decision before implementation.

- [ ] Does the weekly cap of three count milestone projects or themes, and is it a hard limit or a warning?
- [ ] How is each key result updated, and how often? GitHub stars can be pulled automatically, others need manual entry. Should key results have types (a number going up, yes or no, a count)?
- [ ] What counts as a completed milestone when some of its tasks were dropped?
- [ ] What role does the calendar (Google Calendar) play in planning? It was barely discussed.
- [ ] What happens when the user swaps a theme mid-month, or retires or re-links a goal mid-year?
- [ ] Suggested but not agreed: a quarterly checkpoint to reread and rewrite annual goals that no longer feel true.
- [ ] Suggested but not agreed: pairing an outcome key result the user does not fully control (stars) with a controllable one (releases published).
- [ ] How should connectors without nested projects store the theme and milestone relationship in the flat fallback?

**Out of scope:** time tracking in any form, and task managers other than those that meet the capability table above.

## Suggested feature split for Spec Kit

Spec Kit works best with focused features, and the specify step wants the what and why, not the stack. The task manager capability table belongs in the plan step.

| Order | Feature | Covers | Depends on |
| --- | --- | --- | --- |
| 1 | Project classification and onboarding | Import, labels, maintenance and ignored projects, rename write-through, reconciliation | Task manager connector |
| 2 | Weekly planning and review | Milestone creation, three-project commitment, task picking, unfinished-milestone decisions, rollover tracking | 1 |
| 3 | Work categories and statistics | Goal-aligned, maintenance and off-plan split, shared visual language | 2 |
| 4 | Annual planning, goals and key results | Goals, key results, links to themes, per-cycle history | 1 |
| 5 | Monthly planning and review | Theme focus, milestone-count targets, key result updates, snapshots | 2, 4 |
| 6 | Annual review | Rollup of snapshots, next-cycle seeding | 5 |

Feature 2 is the most settled and is the natural first one to implement.
