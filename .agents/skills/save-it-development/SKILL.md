---
name: save-it-development
description: Use when working on `save_it` local development, setup, dev server startup, local checks, Typesense migrations, or code submission workflow.
metadata:
  short-description: save_it development workflow
---

# Save It Development

Use this skill for routine development work in the `save_it` repository.

## Setup

Run from the repository root:

```bash
mise trust
mise install
mix deps.get
```

If `mise.toml` is missing in the current directory, move to the parent directory and retry the `mise` commands.

## Start Local Services

Start dependencies:

```bash
docker compose up
```

After startup:

- Typesense health: `http://localhost:8108/health`
- typelens: `http://localhost:3000`
- typelens auth: `test@example.com` / `pass123456`

Run the bot:

```bash
export TELEGRAM_BOT_TOKEN=<YOUR_TELEGRAM_BOT_TOKEN>
iex -S mix run --no-halt
```

## Local Checks

Prefer the smallest relevant check for the change:

```bash
mix test
mix format
mix credo --strict
mix dialyzer
mix quality
```

`mix quality` is the common check-only suite and must not rewrite files.

## Typesense Migrations

Typesense schema changes live under `priv/typesense/migrations/` as ordered `up`/`down` migration files. Use mix tasks instead of legacy ad-hoc runner scripts:

```bash
mix ts.migrate
mix ts.rollback
mix ts.rollback 20260524000000
mix ts.reset
```

## Commit And PR Workflow

- Use semantic commit messages and semantic branch or PR titles, such as `feat:`, `fix:`, `chore:`, `ci:`, `refactor:`, or `performance:`.
- Create commits with:

```bash
git cz --non-interactive --disable-emoji
```

- Use `gh` for GitHub operations.
- After each push, update the PR title and body when relevant; avoid deleting existing body attachments unless necessary.
