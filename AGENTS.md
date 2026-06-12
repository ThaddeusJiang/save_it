# AGENTS.md

This file provides guidance to coding agents working in this repository.

## Project 

`save_it` is an Elixir Telegram bot that downloads and saves images and videos from the internet, then supports semantic and image-based search through Typesense.

Directory overview:

```text
.
├── CHANGELOG.md             # Curated project changelog following Keep a Changelog with CalVer versions.
├── .agents/                 # Repository-local agent workflow skills.
│   └── skills/
├── .claude/                 # Local Claude configuration.
├── .github/                 # GitHub repository automation.
│   └── workflows/           # GitHub Actions workflow definitions.
├── config/                  # Mix and runtime application configuration.
├── docs/                    # Project documentation.
│   ├── adr/                 # Accepted ADRs; treat them as implementation constraints.
│   ├── assets/              # Documentation images and media assets.
│   ├── deployment/          # Deployment documentation.
│   ├── dev-logs/            # Development log notes.
│   └── development/         # Development guides, including Typesense notes.
├── lib/                     # Application source code.
│   ├── mix/                 # Custom Mix tasks, including Typesense migration tasks.
│   ├── save_it/             # Main application, bot, download, Google Drive, helper, and migration modules.
│   └── small_sdk/           # Small external service clients and download helpers.
├── others/                  # Supporting operational documents and deployment files.
│   ├── postmortem/          # Postmortems for non-trivial bugs or incidents.
│   └── zeabur/              # Zeabur deployment support files.
├── priv/                    # Private runtime resources.
│   └── typesense/           # Typesense schema migrations.
└── test/                    # ExUnit tests for application and SDK behavior.
    └── small_sdk/
```

## Agent Skills

- Use `.agents/skills/save-it-development/SKILL.md` for local setup, dev server startup, local checks, Typesense migrations, and commit workflow.
- Use `.agents/skills/acceptance-testing/SKILL.md` for Docker-based acceptance testing.
- Use `.agents/skills/save-it-release/SKILL.md` for release preparation, verification, and publication.
- Use `.agents/skills/save-it-changelog/SKILL.md` at the end of repository work to maintain `CHANGELOG.md`.

## Postmortems

When solving a non-trivial bug or issue, create `others/postmortem/YYYY-MM-DD-title.md` with:
- What happened
- Root cause
- Fix applied
- What we learned

## Others

- **Always** use fixed versions for dependencies.
- Maintain a repository `CHANGELOG.md` using [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/) structure.
- Use CalVer release headings in `CHANGELOG.md`, for example `## [2026.6.9] - 2026-06-09`.
- At the end of repository work, check `CHANGELOG.md` and update `## [Unreleased]` only for product-focused user-facing features, behavior changes, fixes, removals, security changes, or breaking changes. Do not record docs-only, tests-only, chore-only, formatting-only, CI-only, internal refactor-only, release-process-only, or agent-workflow-only changes.
