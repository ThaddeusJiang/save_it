---
name: save-it-changelog
description: Maintain the save_it repository CHANGELOG.md using Keep a Changelog 1.1.0 with CalVer version headings. Use at the end of repository work, before final response or commit/PR handoff, whenever files changed or a notable project decision, user-facing behavior, operational workflow, documentation, release process, or agent workflow changed.
---

# Save It Changelog

## Overview

Keep `CHANGELOG.md` as the in-repository, human-written summary of notable changes. The project uses Keep a Changelog structure with CalVer release versions, not SemVer.

## Workflow

1. Open `CHANGELOG.md`. If it is missing, create it from the template below.
2. Review the actual repository diff and summarize only notable changes. Do not dump commit logs.
3. Add entries under `## [Unreleased]`, grouped by standard change types.
4. Keep entries concise, user-facing, and understandable without reading the diff.
5. If no notable changelog entry is warranted, leave the file unchanged and mention that in the final response.

## Format Rules

- File name: `CHANGELOG.md`.
- Top section: `## [Unreleased]`.
- Release heading: `## [YYYY.M.D] - YYYY-MM-DD`, for example `## [2026.6.9] - 2026-06-09`.
- Use ISO dates in headings.
- Do not prefix CalVer versions with `v`.
- Keep newest releases first.
- Use these section names when relevant: `Added`, `Changed`, `Deprecated`, `Removed`, `Fixed`, `Security`.
- Remove empty change-type subsections instead of leaving placeholders.
- Keep link references at the bottom when release comparison links exist. Do not invent links for tags that do not exist yet.

## Entry Guidance

- Add `Added` for new features, docs, skills, automation, or capabilities.
- Add `Changed` for changed behavior, workflow, defaults, dependencies, or documented project policy.
- Add `Fixed` for bug fixes.
- Add `Removed` for removed behavior, files, or workflows.
- Add `Security` for vulnerability-related changes.
- Prefer one clear bullet per meaningful change.
- Mention implementation details only when they matter to users, operators, or future maintainers.

## Initial Template

```markdown
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project uses Calendar Versioning.

## [Unreleased]

### Added

- Initial changelog.
```

## Release Rollover

When preparing a release:

1. Move current `Unreleased` entries into a new CalVer heading.
2. Add a fresh empty `## [Unreleased]` section above it.
3. Add or update comparison links only for tags that exist or will be created in the release workflow.
