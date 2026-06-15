# Stable Release Changed Stag Image Reachability

## What happened

Publishing a stable `latest` Docker image could still leave the `ghcr.io/thaddeusjiang/save_it:stag` image unavailable or changed, even after prerelease builds started publishing a floating `stag` tag.

## Root cause

The previous regression covered tag generation only: prereleases produced `stag`, and stable releases produced `latest`. It did not protect the registry state across a stable publish. A stable publish can rewrite package tag associations while pushing `latest` and the release version tag, so the workflow needed to treat `stag` as an existing environment pointer that must be preserved across stable releases.

## Fix applied

The Docker publish workflow now captures the current `stag` manifest digest before stable releases, publishes the stable image, restores `stag` to the captured digest when it existed, and verifies that the digest did not change. The workflow regression test now checks for the capture, restore, and verification steps.

The current missing `stag` tag was restored by running the manual prerelease workflow for `2026.6.12-rc.2`, which republished the prerelease image and moved `stag` back to the prerelease manifest.

## What we learned

Release workflow tests should assert environment pointer invariants, not just generated tag lists. For `latest` releases, `stag` is not an output tag to republish as stable; it is prior registry state that must survive unchanged.
