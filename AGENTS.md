# AGENTS.md

This file provides guidance to coding agents working in this repository.

## Project 

`save_it` is an Elixir Telegram bot that downloads and saves images and videos from the internet, then supports semantic and image-based search through Typesense.

Directory overview:

```text
.
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

## Postmortems

When solving a non-trivial bug or issue, create `others/postmortem/YYYY-MM-DD-title.md` with:
- What happened
- Root cause
- Fix applied
- What we learned

## Others

- **Always** use fixed versions for dependencies.
- **Never** maintain a repository `CHANGELOG.md` in this project. Check change history on the GitHub release page instead.
