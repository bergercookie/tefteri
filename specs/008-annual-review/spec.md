# Feature Specification: Annual Review

**Feature Branch**: `008-annual-review` (developed on the session branch)

**Created**: 2026-11-11

**Status**: Draft

**Input**: User description: "A zoomed-out review of the planning year. It reads the monthly review snapshots stored by feature 007 and never recomputes history. For each goal it shows whether each key result was hit, with the twelve monthly snapshots behind it. It shows which themes served which key results (that year's stored links) and whether the milestones shipped matched the key result movement. It shows the year split of goal-aligned, maintenance and off-plan work (feature 005). It starts the next annual planning session (feature 006) from this year's review. Source: `specs/planning-cycles/source-spec.md`, with the decisions in `specs/planning-cycles/decisions.md`."

## Clarifications

### Session 2026-11-11

- Q: Does the annual review recompute any past month from tasks? → A: No. It reads stored monthly snapshots (feature 007). If a month has no snapshot, the month is shown as missing and nothing is rebuilt from tasks.
- Q: Are goals reviewed for a month or a week? → A: No. Goals are an annual planning and review thing only. Months are run on theme projects and weeks on milestone projects. The annual review is the only place where goals are reviewed.
- Q: Does the annual review change the stored snapshots, links or key results? → A: No. It is read-only. Its only writes are the review notes the user adds. Starting the next year is done in annual planning (feature 006), which owns the seeding rules.
- Q: Does the review decide whether a key result was "hit"? → A: Yes, by one fixed rule. A key result is "hit" when its last value in the year reached the target in the direction from start to target. The screen also shows a second line, "reached by deadline". The rule is shown on the screen.
- Q: Which numbers come from snapshots, and which are live? → A: The totals and the proportion bar come from snapshots only. The drill-down lists tasks live, so it can differ from the bar. The screen says so next to the drill-down.
- Q: Can the user mark a key result as final in a year that is not over? → A: No. The "marked final" control is removed. A year in progress shows no final result.
- Q: What if a monthly review was reopened and saved again? → A: Snapshots are versioned (feature 007). The annual review reads the current version of each month.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See each goal and whether its key results were hit (Priority: P1)

At the end of the year the user opens the annual review. For each goal of that year (one loose sentence about what the year is for) they see its key results (the measurable success criteria of the goal). Each key result shows the start value, the target, the last stored value, a clear "hit" or "missed" result, a second line "reached by deadline", and the monthly values behind it as a small series. The monthly values come from snapshots (the results stored by each monthly review). The user can tell in one look which goals worked and which did not.

**Why this priority**: This is the main reason for the annual review. Without it the year has no honest result.

**Independent Test**: Store twelve monthly snapshots for a year with two goals and three key results. Open the annual review for that year. Check that every key result shows its start, target, last value, hit or missed, reached by deadline, and twelve monthly values, and that no value was recomputed from tasks.

**Acceptance Scenarios**:

1. **Given** a year with stored monthly snapshots, **When** the user opens the annual review for that year, **Then** every goal of the year is listed with its key results, and each key result shows a hit or missed result and its monthly values.
2. **Given** a key result whose target is lower than its start value, **When** its last value in the year is at or below the target, **Then** it is shown as hit.
3. **Given** a key result that was reached in an early month and fell back later, **When** the review is shown, **Then** the result is "missed" because the last value in the year decides, the series still shows the early peak, and the "reached by deadline" line says whether the target was reached by the key result's deadline.
4. **Given** a goal with no key results, **When** the review is shown, **Then** the goal is listed with a quiet note that it had no measurable result and an inline action to open annual planning.
5. **Given** the user enters a value for a key result after the year ended (feature 006 allows value entry in a past year), **When** the review is opened, **Then** the stored snapshots are unchanged and a note says the value moved after the last snapshot.

---

### User Story 2 - See which themes served which key results (Priority: P1)

For each key result the review shows the theme projects (long-running homes for related work) that were linked to it during the year, using the links stored for that year (feature 006). For each theme it shows the milestone projects shipped (small projects with a clear done-state) and the movement of the key result next to it, so the user can see whether six milestones shipped and the key result barely moved. The review does not say a theme was wrong. It shows the facts side by side.

**Why this priority**: The question the year must answer is whether the chosen themes were the right ones. This is the link between planning and results.

**Independent Test**: Store links for two key results and snapshots with per-theme milestone results. Open the review. Check that each key result lists its linked themes with milestones shipped and the key result movement, and that a theme linked to two key results appears under both.

**Acceptance Scenarios**:

1. **Given** a key result linked to two themes, **When** the review is shown, **Then** both themes are listed under it with their milestones shipped for the year.
2. **Given** a theme linked to two key results, **When** the review is shown, **Then** the theme appears under both and its shipped milestones are shown under each. The year total of shipped milestones is not counted twice.
3. **Given** a theme whose shipped milestones are at or above its theme target and a key result that moved less than 25% of its start-to-target span, **When** the review is shown, **Then** both numbers are shown next to each other with a quiet "much shipped, little movement" hint.
4. **Given** a theme with no shipped milestones and a key result that moved a lot, **When** the review is shown, **Then** the hint says the movement did not come from this theme's milestones, and no cause is claimed.
5. **Given** a key result with no usable theme (a flag owned by feature 006), **When** the review is shown, **Then** the key result shows that flag and an inline action to link a theme in annual planning.

---

### User Story 3 - See the year split of work (Priority: P1)

The review shows one proportion bar for the year with the three work categories of feature 005: goal-aligned (in a committed milestone), maintenance (in a maintenance project) and off-plan (goal-type work that was not committed). Below it, a small row per month shows how the split moved during the year. The user can open a drill-down for the tasks of a category. The totals and the bar come from snapshots only. Snapshots hold counts per category and a hidden count, never shares, so percentages are computed on display. The year total is the sum of the months (feature 005 owns these rules). The drill-down lists tasks live and the screen says it may differ from the bar.

**Why this priority**: A yearly result of goals alone would hide maintenance and off-plan work, which is half of how the year was spent.

**Independent Test**: Store snapshots with known counts of the three categories. Open the review. Check that the year bar equals the sum of the months, that each month row matches its snapshot, and that the three categories are always shown separately.

**Acceptance Scenarios**:

1. **Given** twelve snapshots with counts of the three categories, **When** the review is shown, **Then** the year bar equals the sum of the twelve counts and the percentages shown add up to 100%.
2. **Given** a year where the off-plan share grew from month to month, **When** the review is shown, **Then** the monthly row shows the trend without a judgement.
3. **Given** the user opens the drill-down of one category, **When** the list opens, **Then** it shows the tasks of that category for the year as they are now, and it is labelled "live list, may differ from the bar".
4. **Given** a task that was done outside the plan and capped in the old weekly list, **When** the year is shown, **Then** it is still counted, because the year uses the stored counts of feature 005 and not the weekly list.
5. **Given** snapshots with a hidden count (work that could not be shown), **When** the review is shown, **Then** the hidden count is shown as its own part and is not mixed into a category.

---

### User Story 4 - Handle missing months and years with no snapshots (Priority: P1)

Some months have no stored snapshot, because the user skipped the monthly review. The annual review shows these months as missing and does not guess. Each missing month offers an inline action to open that month's review (feature 007). A year with no snapshots at all still opens and says clearly that nothing was stored, with a way to see the goals and key results of that year and their current values. The review never blocks the user: every part opens even when data is missing.

**Why this priority**: The user will not always have done twelve monthly reviews. A review that fails or invents numbers would destroy trust.

**Independent Test**: Store snapshots for 8 of 12 months. Open the review. Check that four months are marked missing and that the totals say they cover 8 months. Then open a year with no snapshot and check that the page loads with a clear empty state.

**Acceptance Scenarios**:

1. **Given** a year with 8 snapshots, **When** the review is shown, **Then** the 4 missing months are marked, each with an inline action to open its monthly review, and every total says how many months it covers.
2. **Given** a missing month, **When** the key result series is shown, **Then** the month has a gap and is not filled with a guessed value.
3. **Given** a year with no snapshots, **When** the user opens the review, **Then** the page loads, says that no monthly review was stored for the year, and shows the goals and key results with their current values and the start and target.
4. **Given** the last snapshot of a key result is older than the last month with a snapshot, **When** the result is computed, **Then** the review uses the latest stored value for that key result and shows the month it came from.
5. **Given** the current year is not over, **When** the user opens the review, **Then** it is shown as "in progress" with the months so far, and no final hit or missed result is claimed.

---

### User Story 5 - Mid-year changes are shown honestly (Priority: P2)

During the year a goal may have been retired, a key result retired or re-targeted, a link changed, or a theme swapped. The review shows these as they were stored (history owned by feature 006). A retired goal is shown with the date it was retired and is not counted as missed. A link that ended in June shows its date range and the months it was active. Stored snapshots are never changed by these edits.

**Why this priority**: Real years change. Showing only the final state would make the review misleading.

**Independent Test**: Retire a goal in June and re-link one theme in August. Open the review. Check that the goal shows as retired with its date, that the link shows two ranges, and that the snapshots read the same as before the edits.

**Acceptance Scenarios**:

1. **Given** a goal retired mid-year, **When** the review is shown, **Then** the goal and its key results are listed as retired with the retirement date, the months before it show their values, and no hit or missed result is claimed.
2. **Given** a key result whose target changed during the year, **When** the review is shown, **Then** the result uses the target at the end of the year, and the history of the change is shown with its date.
3. **Given** a link that was ended and replaced by another theme in August, **When** the review is shown, **Then** both themes are listed with the months in which each link was active, and each theme's milestones are counted only for those months.
4. **Given** a retired or re-linked item, **When** the review is opened, **Then** the stored monthly snapshots read the same as when they were saved.

---

### User Story 6 - Orphaned themes and missing projects (Priority: P2)

A theme that was linked during the year may have disappeared from the task manager. The orphan rule is owned by feature 003. The review follows it: the theme keeps its stored name, label and history, is shown with an orphaned mark (with the reason, for example "archived"), and keeps its numbers. The page never fails because a project is gone.

**Why this priority**: Task managers change over a year. A review that breaks on old data is useless exactly when it is needed.

**Independent Test**: Remove a linked theme from the task manager and sync. Open the review of that year. Check that the theme is shown with its stored name and an orphaned mark, with its stored numbers, and that every part of the page loads.

**Acceptance Scenarios**:

1. **Given** a linked theme that is now orphaned, **When** the review is shown, **Then** it is listed with its stored name and an orphaned mark, and its milestones shipped are shown from the snapshots.
2. **Given** a linked theme that was relabelled (for example to ignored) after the year, **When** the review is shown, **Then** it is still listed under the key results it served, because the review uses the stored links of that year and the label history of feature 003.

---

### User Story 7 - Start next year from this year's review (Priority: P2)

At the end of the review the user can start next year's annual planning with one action. Seeding is owned by feature 006: it offers this year's links and unmet key results as editable suggestions, with a "from year N" input. The review only shows the entry point and passes the year. The review shows how many key results are unmet and how many links exist, so the user knows what to expect. It does not restate the seeding rules.

**Why this priority**: It closes the loop between the review and the next plan, and avoids a blank page.

**Independent Test**: Open the review of a year with one hit and two unmet key results. Use "Start next year". Check that annual planning opens with "from year N" set to the reviewed year and that the review itself created nothing.

**Acceptance Scenarios**:

1. **Given** a reviewed year, **When** the user chooses "Start next year", **Then** annual planning (feature 006) opens with the reviewed year as its "from year N" input. The suggestions, their edits, the handling of orphaned themes, hit key results and existing items follow the rules of feature 006.
2. **Given** the review shows the count of unmet key results (the rule "unmet = last value did not reach the target" is owned by feature 006), **When** the user opens it, **Then** the count matches the count that annual planning offers.
3. **Given** the user leaves annual planning without accepting anything, **When** they return to the review, **Then** nothing was created.

---

### User Story 8 - The review replaces the old Year view for goals (Priority: P3)

The existing Year view and the existing goal review history are folded into the annual review. The user finds the review of a past year in one place. Old reviews stored before this feature (called stored period reviews in feature 006) stay readable in the history view. Old month and week goals, kept as read-only history by feature 006, remain available in the history view and are not part of this review.

**Why this priority**: One place for the year avoids two competing screens, but the review delivers value without removing the old one at once.

**Independent Test**: Open the Year view for a past year. Check that it shows the annual review for that year. Check that the stored period reviews of earlier years are still reachable, and that month and week goals appear only in the read-only history.

**Acceptance Scenarios**:

1. **Given** a past year, **When** the user opens the Year view, **Then** the annual review of that year is shown.
2. **Given** stored period reviews for earlier years in the old format, **When** the user opens the history, **Then** they are shown unchanged.
3. **Given** month and week goal rows, **When** the user opens the annual review, **Then** they are not shown there.

---

### Edge Cases

- A year with no goals and no snapshots: the review opens and shows an empty state with an inline action to open annual planning.
- A key result with no snapshot value in any month: the review shows the start value, the target and a "no value stored" note, and it is not marked hit or missed.
- A key result whose last value in the year is exactly the target: it is hit.
- A key result whose value passed the target and then fell back: the last value decides ("missed"), the peak is visible in the series, and "reached by deadline" shows the earlier success if it happened by the deadline.
- A key result with a deadline inside the year that has already passed: "hit" uses the last value in the year. "Reached by deadline" uses the last value stored on or before the deadline.
- A key result whose deadline is after the end of the year: "reached by deadline" says the deadline is still open and claims nothing.
- A key result whose start and target are equal (span of zero): the 25% hint rule cannot be computed, so no hint is shown.
- A month that was reopened and saved again (feature 007): the review reads the current version of the snapshot.
- Snapshots stored in an older shape (before this feature): they load unchanged and show what they hold. Fields they do not hold are shown as "not stored".
- A theme linked to a key result for only part of the year: its milestones count only for the months of the link.
- Work of a retired goal: it is still counted in the year split, as the work categories of feature 005 do not depend on goals.
- A review opened for a future year: it shows an empty state.
- Large number of themes (more than 20): the list is grouped by key result and collapsible.
- Two connections (task manager accounts): the review shows only the data of the user and the connection that is active.
- Daylight-saving and time-zone changes at the year border: a snapshot belongs to the month it was stored for, not the month of its timestamp.
- The user deletes a note: the screen shows what is lost (the note text), the note is removed, and an undo is offered for a short time.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST provide an annual review for one planning year at a time. It MUST read the stored monthly review snapshots of that year and MUST NOT recompute any past month from tasks or from the task manager.
- **FR-002**: The system MUST list every goal of the year, active or retired, with its key results, and MUST show for each key result the metric, start value, target, deadline, last stored value and the month that value came from.
- **FR-003**: The system MUST mark a key result as "hit" when its last value in the year reached the target in the direction from the start value to the target, and as "missed" otherwise. The rule MUST be shown on the screen. A key result with no stored value MUST NOT be marked hit or missed.
- **FR-004**: The system MUST show for each key result the twelve monthly stored values as a series, with a visible gap for each month that has no snapshot. It MUST NOT fill a gap with a guessed value.
- **FR-005**: The system MUST show for each key result the themes linked to it during the year, using the links stored for that year, and MUST show for each theme the milestones shipped from the snapshots, next to the movement of the key result.
- **FR-006**: The system MUST count a theme's milestones for a link only in the months in which that link was active. A theme linked to several key results MUST appear under each, and the year totals MUST NOT count its milestones more than once.
- **FR-007**: The system MUST show a neutral hint when milestones shipped and key result movement "differ strongly", and MUST NOT claim a cause or say a theme was wrong. "Differ strongly" means: the milestones shipped for the theme are at or above its theme target (stored in the snapshots) while the key result moved less than 25% of its start-to-target span in the months of the link. The hint MUST NOT be shown when the span is zero or the theme has no target.
- **FR-008**: The system MUST show the year split of goal-aligned, maintenance and off-plan work (the work categories of feature 005) as one proportion bar and one row per month. The totals and the bar MUST come from snapshots only. The year bar MUST equal the sum of the months covered. The three categories MUST always be shown separately, and the hidden count MUST be shown as its own part. Percentages MUST be computed on display from stored counts.
- **FR-009**: The system MUST offer a drill-down from each category to the tasks of that category for the year. The drill-down MAY read live data, so its count MAY differ from the bar. The screen MUST say so next to the drill-down.
- **FR-010**: The system MUST mark each month without a snapshot as missing, and every total MUST state how many months it covers. Each missing month MUST offer an inline action to open that month's review.
- **FR-011**: The system MUST open and show a clear empty state for a year with no snapshots, and MUST still show the goals, key results, start values, targets and current values of that year. The empty state MUST offer an inline action to open annual planning.
- **FR-012**: The system MUST show the current year as "in progress" with the months so far and MUST NOT claim a final hit or missed result before the year has ended. There is no control to mark a key result as final.
- **FR-013**: The system MUST show mid-year changes from the history of feature 006: retired goals and key results with their dates, changed targets and deadlines with their dates, and links with their active ranges. A retired goal MUST NOT be counted as missed.
- **FR-014**: The system MUST NOT change any stored snapshot, link or key result. A change made after a snapshot was stored MUST NOT alter what the snapshot shows.
- **FR-015**: The system MUST show an orphaned theme with its stored name and an orphaned mark (and the reason, when feature 003 stores one), and MUST keep its stored numbers. The orphan rule is owned by feature 003. No part of the review MUST fail because a project is orphaned, relabelled or ignored after the year.
- **FR-016**: The system MUST load snapshots stored in an older shape unchanged, and MUST show fields they do not hold as "not stored".
- **FR-017**: The system MUST let the user add a short written note to a goal and to the year in the review. The note MUST be stored, shown again on the next visit and kept private to the user. Notes are the only data the review writes.
- **FR-018**: The system MUST offer a "Start next year" action at the end of the review. It MUST open annual planning (feature 006) with the reviewed year as the "from year N" input. The seeding rules (which key results and links are suggested, how they are edited, how hit key results, orphaned themes and existing items are handled) are owned by feature 006 and MUST NOT be restated or changed here.
- **FR-019**: The review MUST NOT create any goal, key result or link for the next year. Anything created is created in annual planning under the rules of feature 006.
- **FR-020**: The review MUST show the number of unmet key results using the rule of feature 006 ("unmet = last value did not reach the target"), so that the number matches what annual planning offers.
- **FR-021**: The Year view MUST show the annual review for the selected year. The stored period reviews of earlier years (feature 006) MUST stay reachable and load unchanged. Month and week goals MUST NOT appear in the annual review.
- **FR-022**: The review MUST be private to the user, per connection.
- **FR-023**: The review MUST work on phone and desktop widths, in light and dark, and MUST follow the visual language of the work categories of feature 005.
- **FR-024**: The user documentation and the developer documentation MUST describe the annual review, the rule for hit and missed, the "reached by deadline" line, and how missing months are shown, with screenshots made from fake data, in simplified technical English. Existing documentation of the Year view and of goal review history MUST be updated.
- **FR-025**: The system MUST show a second line for each key result, "reached by deadline". It is true when the last value stored on or before the key result's deadline reached the target in its direction. It is shown next to the hit or missed result and does not change it. If the deadline is after the end of the year, the line MUST say the deadline is still open.
- **FR-026**: For each month the system MUST read the current version of the snapshot (feature 007 versions a snapshot when a monthly review is reopened). It MUST NOT read older versions.
- **FR-027**: The system MUST NOT block the user. Every part of the review MUST open with missing, partial or old data. Deleting a note MUST show what is lost and MUST offer undo.
- **FR-028**: The system MUST explain each term the first time it appears on the screen (for example goal, key result, hit, theme, milestone, snapshot, work categories), in one short line or a help hint, and MUST NOT repeat the explanation.
- **FR-029**: The system MUST show a past year's key result values entered after the last snapshot (feature 006 allows value entry in a past year but not changes to its structure) as a separate note and MUST NOT mix them into the snapshot values or into the hit and missed result.

### Key Entities *(include if feature involves data)*

- **Annual review**: The read-only result for one planning year and one user. It holds no recomputed history. It is built from stored snapshots, stored links and the history of feature 006, and it holds the year note and goal notes.
- **Review snapshot (monthly)**: The stored result of one monthly review (feature 007): theme targets and results, key result values, and counts per work category with a hidden count. The annual review reads the current version of up to twelve of them. It is never changed here.
- **Key result outcome**: For one key result and one year: the hit or missed result, the "reached by deadline" line, the last stored value with its month, and the series of monthly values with gaps. It is shown, not stored.
- **Theme contribution**: For one key result and one linked theme: the months the link was active, the milestones shipped in those months, and the key result movement in the same months.
- **Year split**: The sum of the counts per work category over the months that have snapshots, with one row per month. Shown as a proportion bar.
- **Review note**: A short text the user writes for the year or for one goal.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can open the review of a year with 12 snapshots and see, for every key result, whether it was hit, in under 10 seconds and without any other action.
- **SC-002**: The review of any year makes no change to stored snapshots, links or key results. A test that compares them before and after opening the review passes.
- **SC-003**: For a year with known stored data, 100% of the numbers on the review (values, milestones shipped, category counts in the totals and the bar) equal the stored numbers, and the year bar equals the sum of the months in all tests.
- **SC-004**: A year with 0 to 12 snapshots opens without error in 100% of tests, and every total states the months it covers.
- **SC-005**: Retiring, re-linking, re-targeting or orphaning any item after a snapshot was stored changes none of the stored snapshot values shown in the review.
- **SC-006**: Using "Start next year" from the review creates 0 goals, key results or links in the review itself, and the number of unmet key results shown in the review equals the number offered by annual planning in all tests.
- **SC-007**: The review of a year with 20 themes and 10 key results opens in under 2 seconds on a typical phone.
- **SC-008**: In all tests the drill-down is labelled as live, and no total or bar value changes when the drill-down data changes.

## Assumptions

- The first supported task manager is Vikunja. This specification stays task-manager-neutral.
- Dependencies: feature 003 (project labels, label history, orphan handling), feature 004 (milestone completion data), feature 005 (work categories and year totals), feature 006 (goals, key results, links and their history, past-year rules, seeding of the next year) and feature 007 (monthly review snapshots). The annual review cannot show hit and missed results, theme contributions or the year split without them.
- Feature 007 stores in each snapshot the key result values, the per-theme milestone targets and results, and the counts per work category with a hidden count. If a field the review needs is not stored by feature 007, feature 007 must store it. This feature does not add a second store of history.
- A key result is hit by one fixed rule (last value in the year reached the target in its direction). "Reached by deadline" is a second line and does not change the result. Other rules are out of scope. The series still shows the peak.
- Key results have one type in this version: a number with a start value, a target and a deadline (decision in `decisions.md`).
- This feature changes existing behaviour: the Year view becomes the annual review, and the goal review history of earlier years is folded into it for annual goals. Existing tests and documentation for the Year view and for goal reviews will change. Stored period reviews stay readable.
- Month and week goals stay as read-only history (feature 006). The annual review does not show them.
- Goals are an annual planning and review thing only. Months work on theme projects and weeks on milestone projects, so no goal review exists below the year.
- The review notes are the only new stored data of this feature.
- Out of scope: quarterly checkpoints, key result types other than a number, paired controllable key results, any recomputation of past months, charts that export to files, calendar integration, connectors without nested projects, and a control to mark a key result as final.
