## What happened

The repository release guidance described stable versions as `YYYY.M.PATCH`, but it did not explicitly say that the last segment is the calendar day of month. During release preparation, that ambiguity led to the stable version being interpreted as an incrementing monthly patch number instead of the intended release date form.

## Root cause

- The repository-level release convention used a generic `PATCH` label that invited semver-like interpretation.
- Release documentation and workflow examples showed placeholder formats, but not enough concrete date-based examples.
- There was no explicit guardrail stating that a stable release prepared on 2026-05-25 should be `2026.5.25`.

## Fix applied

- Clarified the repository versioning rule in `AGENTS.md` as `YYYY.M.D`.
- Updated the release skill examples and guardrails to state that the final stable segment is the calendar day of month.
- Updated the manual release workflow input description to use date-based examples.

## What we learned

- Date-based versioning rules should use date-shaped placeholders such as `YYYY.M.D`, not generic labels like `PATCH`.
- Release guidance should include one concrete stable example and one prerelease example to reduce operator ambiguity.
