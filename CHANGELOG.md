# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project uses Calendar Versioning for current releases. Older releases
before the CalVer migration retain their original version labels.

## [Unreleased]

### Changed

- Make the save data directory configurable with `SAVE_IT_DATA_DIR`, defaulting to `./data` locally and `/data` in the Docker image, with Docker Compose persisting `/data` on a named volume.
- Simplify photo details to show only the source message URL, original URL, and saved timestamp.

## [2026.6.12-rc.1] - 2026-06-12

### Added

- Add timezone-aware `created at YYYY-MM-DD` captions to media downloaded from URLs, including every item in Telegram media groups. Caption dates use `tzdata` with the standard `TZ` environment variable, defaulting to Tokyo time.
- Store Telegram source message links for indexed media and show them in photo details when a jump URL can be built.
- Save directly uploaded Telegram photos and videos to Typesense, and upload them to Google Drive when Drive is configured.

### Changed

- Show Telegram media captions below photos and videos instead of above the media.
- Show only available fields in photo details instead of rendering empty `N/A` rows.
- Log original-file backup failures for directly uploaded Telegram videos without sending a user-facing message.
- Silently skip unavailable similar media results instead of sending user-facing error messages.

### Fixed

- Save directly uploaded Telegram photos and downloadable videos to local storage backups.
- Save Telegram-provided thumbnails without a user-facing failure message when a user-sent link cannot be downloaded.
- Prevent directly uploaded Telegram videos from crashing when Telegram refuses, fails, or times out while downloading the original file.
- Prevent oversized files from being uploaded to Telegram Bot API.

## [2026.6.9] - 2026-06-09

### Added

- Add `photo detail` command to show detailed information about a saved photo.
- Announce similar photo results so users can discover related media more easily.

### Fixed

- Rewrite Cobalt tunnel URLs to the configured API host to ensure requests are routed correctly.

## [2026.5.25] - 2026-05-25

### Added

- Add rollbackable Typesense migrations.
- Enable colored runtime logger output.
- Store original and download URLs for photos.

### Changed

- Adopt the CalVer release workflow.
- Improve Elixir quality checks.
- Split test and quality workflows.
- Stop maintaining the repository changelog at this point in the project history.
- Refactor download flow data structures.

### Fixed

- Improve Telegram media uploads and Typesense search.
- Fix Telegram media handling.

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

## [0.4.1-rc.3] - 2026-05-24

### Changed

- Publish the third release candidate for `0.4.1`.

## [0.4.1-rc.2] - 2026-05-24

### Changed

- Publish the second release candidate for `0.4.1`.

## [0.4.1-rc.1] - 2026-05-24

### Changed

- Publish the first release candidate for `0.4.1`.

## [0.4.0] - 2026-05-23

### Added

- Support sending Telegram media groups for multi-item media delivery.
- Add local Typesense setup guidance and migration utilities for development and operations.

### Changed

- Improve bot resilience by degrading gracefully when Typesense calls fail.
- Refactor cobalt client error handling to return explicit error tuples instead of raising.

### Fixed

- Avoid crashes from downstream service errors by handling external failures consistently.

## [0.3.0] - 2026-04-26

### Added

- Support `bad.news` video stream downloading via ffmpeg.
- Auto-select the best video quality that fits within Telegram's 50 MB upload limit.
- Add a changelog agent skill.

### Changed

- Add ffmpeg to the Dockerfile for HLS video support.

## [0.2.0] - 2026-04-26

### Highlights

- Add end-to-end media search capability, including photo search and caption search.
- Improve media ingestion reliability with cobalt v10 upgrade and filename parsing fixes.
- Add operations and maintenance capabilities such as the `/delete` command and Sentry integration.

### Breaking Changes

- Upgrade cobalt integration from v7 to v10.
  Deployments using self-hosted or custom cobalt endpoints may need compatibility verification.

### Migration Guide

1. Ensure runtime environment variables are complete for production deployment.
2. Verify your cobalt endpoint is compatible with v10.
3. Deploy `0.2.0`.
4. Run regression checks for key flows: saving media from a direct URL, saving media from messages containing multiple URLs, searching photos and captions, and clearing saved messages with `/delete`.
5. If Sentry is enabled, confirm events are reported correctly in your Sentry project.

### Added

- Support direct media URLs and multiple URLs in one message.
- Add photo search capability.
- Add caption search capability.
- Add capability to update photo captions.
- Add `/delete` command for clearing messages.
- Add Zeabur template for Typesense.

### Changed

- Upgrade cobalt integration from v7 to v10.
- Integrate Sentry for error tracking and logging.
- General maintenance updates.

### Fixed

- Fix missing environment variable handling.
- Fix Typesense `filter_by` format for `belongs_to_id`.
- Fix cobalt v10 filename parsing issue.

## [0.2.0-rc.3] - 2024-11-06

### Added

- Add `/delete` command for clearing messages.

### Fixed

- Fix cobalt v10 API filename parsing.

## [0.2.0-rc.2] - 2024-11-05

### Added

- Add capability to update photo captions.

### Changed

- Upgrade cobalt integration from v7 to v10.

## [0.2.0-rc.1] - 2024-10-23

### Added

- Add photo search capability.
- Add Zeabur template for Typesense.
- Add caption search capability.

### Fixed

- Fix missing environment variable handling.
- Fix Typesense `filter_by` format for `belongs_to_id`.

## [0.1.0] - 2024-10-23

### Added

- Save photos from X.com, YouTube, Instagram, and similar sites.
