# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project uses [Calendar Versioning](https://calver.org/) with the `YYYY.M.PATCH` scheme for new releases.

## [Unreleased]

### Added
- Add Elixir code quality tooling with `Credo`, `Dialyxir`, and `ExDoc`, plus a `mix quality` alias for common local checks.

### Fixed
- Fix Telegram media group uploads for downloaded multi-image posts by accepting file tuples that also carry the source URL metadata.
- Fix Typesense requests crashing in Finch by omitting `receive_timeout` unless a concrete timeout value is provided.
- Fix Docker Compose Cobalt tunnel downloads by returning an internal service URL instead of `localhost`, which is unreachable from the `save_it` container.

### Changed
- Add request and result logging around Typesense photo searches to make empty `/search` responses easier to diagnose in production logs.
- Tune `/search` image semantic retrieval to use a `0.785` vector distance cutoff and log top vector distances for easier relevance calibration.

## [0.4.1] - 2026-05-24

### Added
- Add an ADR for the Docker packaging decision to document using an Elixir base image instead of `mix release`.
- Add a reusable `priv/typesense/migrate.exs` script so Typesense schema operations can be shared by mix tasks and manual maintenance scripts.

### Changed
- Change the Docker and acceptance workflow to use a multi-stage Elixir-based image, compose-driven validation, and a named Typesense volume reused across local worktrees.
- Change Typesense photo indexing to keep both Telegram `file_id` and the original download `url`, while treating `url` as optional for uploads without an external source URL.
- Change Typesense migration tasks to load only runtime config and HTTP dependencies instead of starting the Telegram bot application.

### Fixed
- Fix `mix ts.migrate` false failures when Typesense model initialization finishes after the client timeout but the collection was actually created.
- Fix local media save failures caused by an outdated Typesense `photos` schema that still required `url` and did not include `file_id`.
- Fix Sentry runtime configuration to use `config_env()` so releases do not call `Mix.env()` at boot.

**Full Changelog**: https://github.com/ThaddeusJiang/save_it/compare/v0.4.0...v0.4.1

## [0.4.0] - 2026-05-24

### Added
- feat: Support sending Telegram media groups for multi-item media delivery.
- chore: Add local Typesense setup guidance and migration utilities for development and operations.

### Changed
- refactor: Improve bot resilience by degrading gracefully when Typesense calls fail.
- refactor: Refactor cobalt client error handling to return explicit error tuples instead of raising.

### Fixed
- fix: Avoid crashes from downstream service errors by handling external failures consistently.

**Full Changelog**: https://github.com/ThaddeusJiang/save_it/compare/v0.3.0...v0.4.0

## [0.3.0] - 2026-04-26

### Added
- feat: Support bad.news video URLs with HLS (m3u8) stream downloading via ffmpeg.
- feat: Auto-select best video quality that fits within Telegram's 50MB upload limit.

### Changed
- refactor: Added ffmpeg to Dockerfile for HLS video support.

**Full Changelog**: https://github.com/ThaddeusJiang/save_it/compare/v0.2.0...v0.3.0

## [0.2.0] - 2026-04-26

### Highlights
- chore: Added end-to-end media search capability, including photo search and caption search.
- chore: Improved media ingestion reliability with cobalt v10 upgrade and filename parsing fixes.
- chore: Added operations and maintenance capabilities such as `/delete` command and Sentry integration.

### Breaking Changes
- chore: Upgraded cobalt integration from v7 to v10.
  - Impact: deployments using self-hosted/custom cobalt endpoints may need compatibility verification.
  - Action: validate cobalt v10 API behavior in staging before production rollout.

### Migration Guide
1. Ensure runtime environment variables are complete for production deployment.
2. Verify your cobalt endpoint is compatible with v10.
3. Deploy `v0.2.0`.
4. Run regression checks for key flows:
   - save media from direct URL
   - save media from messages containing multiple URLs
   - search photos and captions
   - clear saved messages with `/delete`
5. If Sentry is enabled, confirm events are reported correctly in your Sentry project.

### Added
- feat: Support direct media URLs and multiple URLs in one message. ([#37](https://github.com/ThaddeusJiang/save_it/pull/37))
- feat: Add photo search capability. ([#12](https://github.com/ThaddeusJiang/save_it/pull/12))
- feat: Add caption search capability. ([#21](https://github.com/ThaddeusJiang/save_it/pull/21))
- feat: Add capability to update photo captions. ([#24](https://github.com/ThaddeusJiang/save_it/pull/24))
- feat: Add `/delete` command for clearing messages. ([#31](https://github.com/ThaddeusJiang/save_it/pull/31))

### Changed
- refactor: Upgrade cobalt integration from v7 to v10. ([#26](https://github.com/ThaddeusJiang/save_it/pull/26))
- refactor: Integrate Sentry for error tracking and logging. ([#35](https://github.com/ThaddeusJiang/save_it/pull/35))

### Fixed
- fix: Fix missing environment variable handling. ([#16](https://github.com/ThaddeusJiang/save_it/pull/16))
- fix: Fix Typesense `filter_by` format for `belongs_to_id`. ([#19](https://github.com/ThaddeusJiang/save_it/pull/19))
- fix: Fix cobalt v10 filename parsing issue. ([#28](https://github.com/ThaddeusJiang/save_it/pull/28))

### Chore
- chore: Add Zeabur template for Typesense. ([#18](https://github.com/ThaddeusJiang/save_it/pull/18))
- chore: General maintenance updates.

**Full Changelog**: https://github.com/ThaddeusJiang/save_it/compare/v0.1.0...v0.2.0

## [0.2.0-rc.3] - 2024-11-06

### Changed
- fix: cobalt v10 api - parse filename failed (fix #27) ([#28](https://github.com/ThaddeusJiang/save_it/pull/28))
- feat: `/delete` command for clear messages (resolve #25) ([#31](https://github.com/ThaddeusJiang/save_it/pull/31))

**Full Changelog**: https://github.com/ThaddeusJiang/save_it/compare/v0.2.0-rc.2...v0.2.0-rc.3

## [0.2.0-rc.2] - 2024-11-05

### Added
- feat: update photo's caption ([#24](https://github.com/ThaddeusJiang/save_it/pull/24))
- feat: upgrade cobalt v7->v10 ([#26](https://github.com/ThaddeusJiang/save_it/pull/26))

**Full Changelog**: https://github.com/ThaddeusJiang/save_it/compare/v0.2.0-rc.1...v0.2.0-rc.2

## [0.2.0-rc.1] - 2024-10-23

### Added
- feat: search photos ([#12](https://github.com/ThaddeusJiang/save_it/pull/12))
- feat: search photo's caption ([#21](https://github.com/ThaddeusJiang/save_it/pull/21))

### Fixed
- fix: miss get_env ([#16](https://github.com/ThaddeusJiang/save_it/pull/16))
- fix: `filter_by => belongs_to_id:123` ([#19](https://github.com/ThaddeusJiang/save_it/pull/19))

### Chore
- chore: zeabur template for Typesense ([#18](https://github.com/ThaddeusJiang/save_it/pull/18))

**Full Changelog**: https://github.com/ThaddeusJiang/save_it/compare/v0.1.0...v0.2.0-rc.1

## [0.1.0] - 2024-10-23

### Added
- feat: Save photos from X.com, YouTube, Instagram, and more.
- feat: Demo video: https://github.com/user-attachments/assets/4a375cab-7124-44f3-994e-0cb026476d39

**Full Changelog**: https://github.com/ThaddeusJiang/save_it/commits/v0.1.0
