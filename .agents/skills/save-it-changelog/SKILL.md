---
name: save-it-changelog
description: Maintain the save_it repository CHANGELOG.md using Keep a Changelog 1.1.0 with dated, v-prefixed SemVer headings. Use at the end of repository work, before final response or commit/PR handoff, when user-facing product behavior, features, fixes, removals, security changes, or breaking changes changed.
---

# Save It Changelog

## Overview

Keep `CHANGELOG.md` as the in-repository, human-written summary of notable changes. The project uses Keep a Changelog structure with `v`-prefixed SemVer release tags and ISO release dates. Preserve historical CalVer headings unchanged.

## Workflow

1. Open `CHANGELOG.md`. If it is missing, create it from the template below.
2. Review the actual repository diff and summarize only notable user-facing product changes. Do not dump commit logs.
3. Add entries under `## [Unreleased]`, grouped by standard change types.
4. Keep entries concise, user-facing, and understandable without reading the diff.
5. If the diff is only docs, tests, chores, internal refactors, formatting, CI, release plumbing, agent skills, or other maintainer-only workflow changes, leave the file unchanged and mention that no product changelog entry is warranted.

## Format Rules

- File name: `CHANGELOG.md`.
- Top section: `## [Unreleased]`.
- Stable release heading: `## [vMAJOR.MINOR.PATCH] - YYYY-MM-DD`, for example `## [v0.5.0] - 2026-09-04`.
- Prerelease heading: `## [vMAJOR.MINOR.PATCH-rc.N] - YYYY-MM-DD`.
- Use ISO dates in headings and keep the date outside the release tag.
- Keep the corresponding `mix.exs` version unprefixed.
- Keep newest releases first.
- Use these section names when relevant: `Added`, `Changed`, `Deprecated`, `Removed`, `Fixed`, `Security`.
- Remove empty change-type subsections instead of leaving placeholders.
- Keep link references at the bottom when release comparison links exist. Do not invent links for tags that do not exist yet.

## Entry Guidance

- Add `Added` for new user-facing features or product capabilities.
- Add `Changed` for user-visible behavior, defaults, or compatibility changes.
- Add `Fixed` for bug fixes.
- Add `Removed` for removed user-facing behavior or product capabilities.
- Add `Security` for vulnerability-related changes.
- Prefer one clear bullet per meaningful change.
- Do not record docs-only, tests-only, chore-only, formatting-only, CI-only, internal refactor-only, release-process-only, or agent-workflow-only changes.
- Mention implementation details only when they explain a user-visible outcome or required operator action.

## Initial Template

```markdown
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial changelog.
```

## Release Rollover

When preparing a release:

1. Move current `Unreleased` entries into a new dated, `v`-prefixed SemVer heading.
2. Add a fresh empty `## [Unreleased]` section above it.
3. Add or update comparison links only for tags that exist or will be created in the release workflow.
