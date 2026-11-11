# Specification Quality Checklist: Weekly Planning and Review with Milestone Projects

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

- This feature changes existing behaviour: the hard cap becomes a warning, the unit of commitment becomes the milestone, carry and backlog become the new decisions, and goals leave the weekly flow. Existing tests and docs will change (listed in Assumptions).
- Goals are annual only, as the project owner corrected. FR-015 removes goals from the weekly flow.
- The spec mentions Vikunja only in Assumptions.
- Feature 007 (monthly focus) is read only when it exists. The spec defines the behaviour when it does not.
- The 200-task limit on "done outside the plan" is kept from existing behaviour.
- No unresolved questions. The completion rule and the cap rule come from decisions.md.
