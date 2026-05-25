# AGENTS.md

This file provides guidance to coding agents working in this repository.

## Project Snapshot

- Project: `save_it`
- Stack: Elixir (Telegram bot), Docker, external downloader/search services
- Primary goal: ship practical features quickly with controlled complexity
- Versioning: CalVer `YYYY.M.PATCH` for stable releases, with git tags using the same value without a `v` prefix, and prereleases such as `YYYY.M.PATCH-rc.N`

## Environment and Tooling

Prefer these commands and tools:

1. Environment setup
- `mise trust`
- `mise install`
- If `mise.toml` is missing in current directory, run in parent directory.

2. Repository commands
- Install deps: `mix deps.get`
- Start local dependencies: `docker compose up`
- Run app: `iex -S mix run --no-halt`
- Run tests: `mix test`

## Change Management

When new tasks or constraints appear:

- Update task checklist.
- Update acceptance checklist.
- Update related docs when relevant.
- Do not maintain a repository `CHANGELOG.md` in this project. Check change history on the GitHub release page instead.
- When a project-level decision changes team workflow or release handling, update the relevant ADRs, docs, and release tooling as part of the same task.
- Treat these updates as part of the current task, not optional follow-up.

## Docker Image Policy

- Use pinned image versions in `docker-compose.yml`.
- Do not use floating tags like `latest`.

## Acceptance Checklist

Before finishing, verify all items:

- [ ] Requirement is implemented end-to-end.
- [ ] Scope is minimal and aligned with project goal.
- [ ] Existing behavior is not unintentionally broken.
- [ ] Commands/tests needed for confidence were run, or skipped with reason.
- [ ] Relevant docs/checklists are updated if scope or constraints changed.
- [ ] Output is clear for direct handoff.

## Postmortems

When solving a non-trivial bug or issue, create `others/postmortem/YYYY-MM-DD-title.md` with:
- What happened
- Root cause
- Fix applied
- What we learned
