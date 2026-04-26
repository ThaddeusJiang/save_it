---
name: changelog
description: Maintain and update CHANGELOG.md using Keep a Changelog 1.1.0 conventions with SemVer-friendly release sections, Unreleased workflow, and consistent change categorization.
metadata:
  short-description: Keep a Changelog workflow
---

# Changelog

Use this skill when the user asks to create, update, normalize, or release `CHANGELOG.md`.

## Standard

- Follow Keep a Changelog `1.1.0` structure.
- Treat changelog as human-curated release notes, not a raw commit dump.
- Use reverse chronological order.
- Keep an `[Unreleased]` section at the top.
- Use ISO dates: `YYYY-MM-DD`.
- Follow SemVer version headers: `## [x.y.z] - YYYY-MM-DD`.

## Allowed Change Types

Use these sections when needed (omit empty ones):

- `Added`
- `Changed`
- `Deprecated`
- `Removed`
- `Fixed`
- `Security`

## Editing Workflow

1. Read current `CHANGELOG.md` and identify whether this is:
- unreleased note update
- formal release cut
- historical format normalization

2. Collect candidate changes from relevant sources:
- merged PR descriptions
- release notes drafts
- issue references
- commit history (for discovery only)

3. Rewrite changes into user-facing language:
- describe impact and behavior changes
- group by change type
- merge duplicate items
- remove low-signal internal noise

4. Update `CHANGELOG.md`:
- ensure `[Unreleased]` exists and stays at top
- add entries under correct type headings
- keep headings in canonical order
- keep links at bottom consistent if project uses link references

5. If this is a release cut:
- move `[Unreleased]` items into new version section
- stamp release date in `YYYY-MM-DD`
- create a fresh empty `[Unreleased]` section
- update compare links (`[Unreleased]`, previous version, new version)

## Output Template

```markdown
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- ...

## [1.2.3] - 2026-04-26

### Fixed
- ...
```

## Quality Checklist

Before finishing, verify:

- changelog is understandable for users who did not read commits
- no empty section blocks are kept unless project explicitly prefers them
- versions are strictly descending
- date format is valid ISO `YYYY-MM-DD`
- wording is consistent (imperative or past tense, chosen once)
- no contradictory entries across sections

## Guardrails

- Do not auto-generate changelog directly from git log and paste as-is.
- Do not hide breaking behavior changes under vague wording.
- Do not include speculative or unshipped work in released sections.
