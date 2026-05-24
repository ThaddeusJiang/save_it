---
name: save-it-release
description: Prepare, verify, and publish `save_it` releases by updating `CHANGELOG.md` and `mix.exs`, creating the release commit and tag, and publishing a GitHub release with notes extracted from the changelog. Use when the user asks to cut a stable release, prepare a prerelease, or verify release readiness for this repository. This repository uses CalVer `YYYY.M.PATCH` and prerelease tags such as `YYYY.M.PATCH-rc.N`.
---

# Save It Release

Use this skill when the task is specifically about the `save_it` release flow.

This repository uses:
- `CHANGELOG.md` as the source of release notes
- `mix.exs` `version` as the application version
- CalVer `YYYY.M.PATCH` for stable versions, for example `2026.5.1`
- git tags that match the version string directly, for example `2026.5.1`
- GitHub Release publication to trigger `.github/workflows/release.yml`
- `.github/workflows/release-manual.yml` for manual prereleases such as `2026.5.2-rc.1`

## Workflow

1. Read the current release state.
2. Decide whether this is release preparation, stable release publication, or manual prerelease publication.
3. Align `CHANGELOG.md` and `mix.exs`.
4. Verify release notes and git state.
5. Execute the matching release path.
6. Report the exact tag, commit, release URL, and workflow status.

## Preflight

Run:

```bash
git fetch --tags --prune
git status --short --branch
git tag --sort=-version:refname | sed -n '1,20p'
```

Rules:
- Prefer cutting stable releases from `main`.
- If the tree is dirty, stop and surface the changed files before continuing.
- Check whether the target stable tag or GitHub release already exists before creating anything.

Use the helper script for a quick snapshot:

```bash
.agents/skills/save-it-release/scripts/check_release_state.sh YYYY.M.PATCH
```

## Release Preparation

When the user asks to prepare a release but not publish it yet:

1. Update `CHANGELOG.md`.
- Keep `[Unreleased]` at the top.
- Move shipped items into `## [YYYY.M.PATCH] - YYYY-MM-DD`.
- Add the compare link for the new version.
- Keep entries user-facing and in English.
2. Update `mix.exs`:

```elixir
version: "YYYY.M.PATCH"
```

3. Show the diff for `CHANGELOG.md` and `mix.exs`.
4. Do not tag or publish unless the user explicitly asks to release.

If changelog drafting is still needed, also use `.agents/skills/changelog/SKILL.md`.

## Stable Release Publication

When the user asks to publish a stable release:

1. Confirm the released version exists in both `CHANGELOG.md` and `mix.exs`.
2. Extract release notes with:

```bash
.agents/skills/save-it-release/scripts/extract_release_notes.sh YYYY.M.PATCH
```

3. Commit release metadata changes using the repository convention:

```bash
git add CHANGELOG.md mix.exs
git commit -m "chore(release): bump version to YYYY.M.PATCH"
```

4. Create and push the stable tag:

```bash
git tag -a YYYY.M.PATCH -m "YYYY.M.PATCH"
git push origin main
git push origin refs/tags/YYYY.M.PATCH
```

5. Publish the GitHub release from the extracted notes:

```bash
tmpfile="$(mktemp)"
.agents/skills/save-it-release/scripts/extract_release_notes.sh YYYY.M.PATCH > "$tmpfile"
gh release create YYYY.M.PATCH \
  --verify-tag \
  --title "YYYY.M.PATCH" \
  --notes-file "$tmpfile"
rm -f "$tmpfile"
```

6. Check whether the `Release` workflow was triggered:

```bash
gh run list --limit 5
```

If the user wants more confidence before release, run the acceptance flow from `.agents/skills/acceptance-testing/SKILL.md`.

## Manual Prerelease Publication

When the user asks for a prerelease:

1. Keep the version in the repository's CalVer prerelease form, for example `2026.5.2-rc.1`.
2. Prefer the existing GitHub Actions workflow instead of manually crafting a prerelease:

```bash
gh workflow run "Release (manual)" -f tag=YYYY.M.PATCH-rc.N
```

3. This workflow publishes a GitHub prerelease and triggers Docker publish with prerelease semantics.

## Guardrails

- Never publish a stable release from a dirty working tree.
- Never create a stable release if `mix.exs` and `CHANGELOG.md` disagree on the version.
- Never use a non-CalVer stable version format in this repository unless the project convention is explicitly changed again.
- Never add a `v` prefix to new release tags in this repository.
- Never invent release notes from raw commit history when the matching changelog section is missing.
- Never recreate an existing tag or GitHub release.
- Never use the manual prerelease workflow for a normal stable release when direct GitHub release publication is intended.

## Related Files

- `CHANGELOG.md`
- `mix.exs`
- `.github/workflows/release.yml`
- `.github/workflows/release-manual.yml`
- `.agents/skills/changelog/SKILL.md`
- `.agents/skills/acceptance-testing/SKILL.md`

## Resources

- `scripts/extract_release_notes.sh`
- `scripts/check_release_state.sh`
