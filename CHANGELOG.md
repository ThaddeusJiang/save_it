# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-04-26

### Highlights
- Added end-to-end media search capability, including photo search and caption search.
- Improved media ingestion reliability with cobalt v10 upgrade and filename parsing fixes.
- Added operations and maintenance capabilities such as `/delete` command and Sentry integration.

### Breaking Changes
- Upgraded cobalt integration from v7 to v10.
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
- Support direct media URLs and multiple URLs in one message. ([#37](https://github.com/ThaddeusJiang/save_it/pull/37))
- Add photo search capability. ([#12](https://github.com/ThaddeusJiang/save_it/pull/12))
- Add caption search capability. ([#21](https://github.com/ThaddeusJiang/save_it/pull/21))
- Add capability to update photo captions. ([#24](https://github.com/ThaddeusJiang/save_it/pull/24))
- Add `/delete` command for clearing messages. ([#31](https://github.com/ThaddeusJiang/save_it/pull/31))

### Changed
- Upgrade cobalt integration from v7 to v10. ([#26](https://github.com/ThaddeusJiang/save_it/pull/26))
- Integrate Sentry for error tracking and logging. ([#35](https://github.com/ThaddeusJiang/save_it/pull/35))

### Fixed
- Fix missing environment variable handling. ([#16](https://github.com/ThaddeusJiang/save_it/pull/16))
- Fix Typesense `filter_by` format for `belongs_to_id`. ([#19](https://github.com/ThaddeusJiang/save_it/pull/19))
- Fix cobalt v10 filename parsing issue. ([#28](https://github.com/ThaddeusJiang/save_it/pull/28))

### Chore
- Add Zeabur template for Typesense. ([#18](https://github.com/ThaddeusJiang/save_it/pull/18))
- General maintenance updates.

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
- Save photos from X.com, YouTube, Instagram, and more.
- Demo video: https://github.com/user-attachments/assets/4a375cab-7124-44f3-994e-0cb026476d39

**Full Changelog**: https://github.com/ThaddeusJiang/save_it/commits/v0.1.0
