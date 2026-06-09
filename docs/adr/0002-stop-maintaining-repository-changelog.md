# Stop Maintaining Repository Changelog

Superseded by [ADR 0003: Maintain Repository Changelog](0003-maintain-repository-changelog.md).

## Context and Problem Statement

`save_it` is a small project optimized for shipping practical features with controlled complexity. Maintaining a hand-written repository `CHANGELOG.md` adds a second release-writing workflow on top of pull requests, git history, ADRs, and the GitHub release page.

That duplication is no longer paying for itself. We need a simpler default that removes the maintenance burden while still keeping release publication and project-level decisions understandable.

## Considered Options

* Keep maintaining `CHANGELOG.md` in the repository
* Stop maintaining `CHANGELOG.md` and rely on the GitHub release page, ADRs, and git history
* Auto-generate and commit changelog content from git history during releases

## Decision Outcome

Chosen option: "Stop maintaining `CHANGELOG.md` and rely on the GitHub release page, ADRs, and git history", because it removes duplicate documentation work and better matches the project's bias toward low-overhead maintenance.

### Consequences

* Good, because feature work and releases no longer require keeping a curated changelog file in sync.
* Good, because project-level workflow decisions can still be documented explicitly in ADRs.
* Good, because the GitHub release page can provide release notes without committing changelog content into the repository.
* Bad, because repository readers lose a single in-tree chronological summary of product changes.
* Bad, because release note quality now depends on GitHub release drafting or manual release descriptions.
