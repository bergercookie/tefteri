# Specification Quality Checklist: Work Categories and Statistics

**Purpose**: Validate specification completeness and quality before proceeding to planning

**Created**: 2026-11-11

**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No implementation details (languages, frameworks, APIs)
- [x] Focused on user value and business needs
- [x] Written for non-technical stakeholders
- [x] All mandatory sections completed

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain
- [x] Requirements are testable and unambiguous
- [x] Success criteria are measurable
- [x] Success criteria are technology-agnostic (no implementation details)
- [x] All acceptance scenarios are defined
- [x] Edge cases are identified
- [x] Scope is clearly bounded
- [x] Dependencies and assumptions identified

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria
- [x] User scenarios cover primary flows
- [x] Feature meets measurable outcomes defined in Success Criteria
- [x] No implementation details leak into specification

## Notes

- Cross-spec resolutions of 2026-11-11 applied (5, 2, 9): the category is stored at first sight of the completion and never recomputed; month is the sum of days and year the sum of months; 005 needs 004 with no fallback; counts and the hidden count are stored, never shares; words are "work categories" with a helper line for goal-aligned; no-time-tracking is owned here (FR-014); orphans refer to 003.
- Four defaults are documented in Clarifications for the owner to confirm: the project at completion decides the category; unclassified or no-project tasks are off-plan with an "unsorted" note; ignored-project tasks are hidden but counted in one quiet line; past categories stay stable when labels change or commitments are edited.
- FR-011 says "on the server". This states where the shared definition lives, not a stack choice. Review during planning if it is seen as too technical.
- The assumption about recording the project at first sight of completion depends on what the task manager reports. Check this in the plan for Vikunja.
- An edited past commitment does not change stored categories (FR-007). Feature 004 must use the weekly list from this feature and must not restate the 200-task cap; its current text (kept limit of 200, FR-022) still needs that fix.
- Usability: empty-state action, term explanations and never-block rules are in FR-027 and FR-028. This feature has no destructive choice, so no undo is needed.
- The spec mentions Vikunja only in Assumptions.
- This feature modifies existing behaviour: 200-task cap, client-side calculations, week/month/year views. Existing tests and docs will change.
