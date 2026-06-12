# Upgrade Dependencies and Replace Tesla with Req

## Context

The project currently depends on Tesla directly and uses it in Telegram, Google Drive, and Google OAuth device-flow HTTP clients. `ex_gram` is pinned through a broad requirement and defaults to its Tesla adapter unless configured otherwise.

## Problem Definition

Upgrade direct dependencies to current stable versions with exact version requirements, migrate all application HTTP client code away from Tesla, and configure `ex_gram` to use Req.

## Candidate Solutions

- Keep Tesla for non-`ex_gram` clients and only configure `ex_gram` to use Req.
  - Pros: smallest code change.
  - Cons: does not satisfy the project goal of no longer using Tesla.
- Migrate every in-repo Tesla client to Req and remove the direct Tesla dependency.
  - Pros: one HTTP client, simpler dependency graph, removes old Tesla config.
  - Cons: touches more tests and HTTP request construction.
- Wrap all HTTP clients behind a new behaviour before migration.
  - Pros: more test seams.
  - Cons: unnecessary abstraction for the current small codebase.

## Selected Solution

Migrate the existing Telegram, Google Drive, and Google OAuth clients to Req, configure `ex_gram` with `ExGram.Adapter.Req`, remove Tesla and Hackney from direct dependencies if they are no longer needed, and pin direct dependency versions exactly.

## Architecture/Data Flow

Runtime config provides tokens and base URLs. Each HTTP module builds a `Req` request with module-specific base URL, headers, and optional test request options from application env. Tests inject Req adapters or local HTTP servers to observe request bodies without external network calls.

## Risks and Mitigations

- `ex_gram` API changes between `0.53.0` and `0.67.0`: run focused bot tests and compile with warnings as errors.
- Multipart request construction may differ from Tesla: add/adjust tests around Telegram media groups and Google Drive uploads.
- Dependency graph may still include Tesla transitively: verify with `mix deps.tree` and `rg`.
- Broad dependency changes may surface pre-existing dependency warnings: separate dependency warnings from project compile failures.

## Validation Checklist

- [x] `SmallSdk.Telegram` sends media-group multipart requests through Req.
- [x] `SmallSdk.Telegram` downloads Telegram files through Req.
- [x] Google Drive uploads use Req and preserve auth, metadata, and file content.
- [x] Google OAuth device flow uses Req form requests.
- [x] `ex_gram` is configured to use `ExGram.Adapter.Req`.
- [x] Direct dependencies use exact stable versions.
- [x] Tesla is absent from direct dependencies and project code.
- [x] Hackney is absent from direct dependencies and project code; it remains transitive through upstream packages.
- [x] Focused tests pass.
- [x] `mix format` passes.
- [x] `mix compile --warnings-as-errors` passes.

Note: `req` is pinned to `0.5.18`, the latest version compatible with `ex_gram 0.67.0` because `ex_gram` currently declares `req ~> 0.5.0` for its Req adapter.

## Execution Decision

direct-do
