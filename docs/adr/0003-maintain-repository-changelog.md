# Maintain Repository Changelog

## Context and Problem Statement

ADR 0002 stopped maintaining a repository `CHANGELOG.md` to reduce duplicate release-writing work. The project now needs an in-tree, human-readable change summary that is available outside the GitHub release page and can be updated continuously as work is completed.

The changelog should stay lightweight, curated, and compatible with the existing CalVer release convention.

## Considered Options

* Continue relying only on GitHub releases, ADRs, and git history
* Maintain a repository `CHANGELOG.md` using Keep a Changelog 1.1.0 and CalVer headings
* Auto-generate changelog content from git history during releases

## Decision Outcome

Chosen option: "Maintain a repository `CHANGELOG.md` using Keep a Changelog 1.1.0 and CalVer headings", because it gives readers a discoverable in-tree summary while keeping release notes curated for humans.

This decision supersedes ADR 0002.

### Consequences

* Good, because notable changes are visible in the repository without relying on GitHub release pages.
* Good, because `Unreleased` gives agents and maintainers a clear place to record changes as work is completed.
* Good, because Keep a Changelog gives the file a familiar structure while CalVer keeps release naming aligned with the project.
* Bad, because maintainers and agents must keep one more documentation artifact in sync with actual changes.
* Bad, because low-signal entries can reduce changelog usefulness if agents record implementation noise instead of notable changes.
