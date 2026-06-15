# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project uses Calendar Versioning for current releases. Older releases
before the CalVer migration retain their original version labels.

## [Unreleased]

### Changed

- Make the save data directory configurable with `SAVE_IT_DATA_DIR`, defaulting to `./data` locally and `/data` in the Docker image, with Docker Compose persisting `/data` on a named volume.

### Fixed

- Use random UUIDv7 filenames for downloaded resources while preserving the original file extension.
- Preserve URL video preview aspect ratios by sending accurate display dimensions and square-pixel Telegram covers/thumbnails.

## [2026.6.15] - 2026-06-15

### Added

- Show chat type, public visibility, bot admin status, and bot Privacy Mode status in the `/about` command.
- Store public link preview thumbnail URLs in Typesense for URL media saves and webpage preview fallbacks.

### Changed

- Keep ordinary informational logs uncolored and reserve green logs for successful resource creation events.
- Reduce default runtime log noise by moving successful intermediate download, file-write, link-preview, search, and video-probing details out of the normal log stream.
- Use YouTube Open Graph titles as captions for URL-only saves, and keep X captions based on Open Graph descriptions with title fallback.

### Fixed

- Fix Zeabur Cobalt cookie setup to use a file config at `/cookies.json` instead of mounting a volume as a file.
- Keep GHCR prerelease images reachable through the `stag` tag after stable `latest` images are published.
- Log link preview metadata fetch failures so missing URL captions and thumbnail URLs can be diagnosed from runtime logs.
- Send URL-downloaded media back to the source Telegram topic, build private supergroup topic source message URLs with the message thread id, and stop indexing the unused `source_message_id` field.
- Stop storing invalid Telegram `source_message_url` values for private DM saves, where Telegram does not provide a direct message URL.
- Store resolved media download URLs in Typesense for successful URL photo, video, HLS, and multi-image saves.

## [2026.6.14] - 2026-06-14

### Added

- Support downloading X resources that require login or verification when self-hosted Cobalt is configured with local cookies.

### Changed

- Improve photo search to support caption full-text matching and high-confidence image semantic matching.
- Upgrade the bundled Cobalt service image from v10 to v11 for local and Zeabur deployments.
- Use user-provided Telegram text as captions for URL and photo saves, and fall back to URL Open Graph descriptions when a link has no user description.

### Fixed

- Fail application startup when `TELEGRAM_BOT_TOKEN` is missing instead of starting the bot with repeated ExGram token warnings.
- Prevent `/similar` photo commands from crashing when Telegram delivers the command as a photo command update instead of a plain photo message.
- Index Telegram photo captions delivered by ExGram as text updates so caption search can find directly uploaded photos.
- Preserve downloaded MP4 video display dimensions when sending to Telegram, and prepare uploads for streaming playback when possible.

## [2026.6.13] - 2026-06-13

### Changed

- Simplify photo details to show only the source message URL, original URL, and saved timestamp.
- Upgrade Telegram and HTTP dependencies, and run Telegram, Google Drive, and Google OAuth requests through Req instead of Tesla.
- Keep HTTP logs at request-summary level instead of dumping full request and response bodies at debug level.

### Fixed

- Save Telegram video thumbnails as the preferred searchable cover for URL video downloads, falling back to webpage preview images only when Telegram does not provide a thumbnail.

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
- Prevent `/similar` results from echoing the just uploaded Telegram media back into the chat.
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
