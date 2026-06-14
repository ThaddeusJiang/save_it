# GHCR Stag Tag Dropped on Latest Release

## What happened

After a stable `latest` image was published to GHCR, the expected `ghcr.io/thaddeusjiang/save_it:stag` image tag was no longer available. A direct registry check returned `not found` for `stag`, while `latest` still resolved to a multi-platform manifest.

## Root cause

The reusable Docker publish workflow did not publish a floating `stag` tag for prereleases. Prerelease builds only pushed the immutable release version tag, and stable releases pushed `latest` plus the same version tag. When the version tag moved to the stable image, no separate prerelease tag remained to keep the staging image reachable.

## Fix applied

The Docker metadata step now publishes `stag` when `inputs.is_prerelease` is true. Stable releases continue to publish `latest` and the requested version tag. A workflow regression test now checks that prerelease builds include `stag` and stable builds keep the existing `latest` behavior.

## What we learned

Prerelease images need an environment-style floating tag in addition to the release version tag. Otherwise, promoting or republishing the same version as stable can leave staging without a durable image reference.
