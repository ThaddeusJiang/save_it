---
name: save-it-release
description: Prepare, verify, and publish `save_it` releases by updating `mix.exs`, creating a dated changelog section, tagging a v-prefixed SemVer release, and publishing a dated GitHub Release. Use when the user asks to cut a stable release, prepare an rc prerelease, or verify release readiness for this repository.
---

# Save It Release

Use this skill when the task is specifically about the `save_it` release flow.

This repository uses:
- `mix.exs` `version` as the application version, without a `v` prefix, for example `0.5.0`
- `v`-prefixed SemVer Git tags for stable releases, for example `v0.5.0`
- `-rc.N` prerelease tags, for example `v0.5.0-rc.1`
- dated changelog headings, for example `## [v0.5.0] - 2026-09-04`
- dated GitHub Release titles, for example `save_it v0.5.0 - 2026-09-04`
- GitHub Release publication to trigger `.github/workflows/release.yml`
- `.github/workflows/release-manual.yml` for manual prereleases

Historical CalVer tags and changelog headings remain unchanged.

## Release Rules

- Change `mix.exs` `version` only while checked out on `main`. A version bump commit that contains only version and release metadata is this repository's only direct-to-`main` exception.
- Require an explicit target version or bump level; do not derive a SemVer version from the date.
- Keep the `v` prefix in Git tags and release-note headings, but omit it from `mix.exs`.
- Keep release dates outside tags and use the same ISO `YYYY-MM-DD` date in the changelog and GitHub Release title.
- The bump version commit message must be exactly the target release tag, for example `v0.5.0` or `v0.5.0-rc.1`.
- Create the release tag on the bump version commit.
- Maintain `CHANGELOG.md` only for product-focused user-facing features, behavior changes, fixes, removals, security changes, or breaking changes.
- Before publishing a release or prerelease, roll current `Unreleased` entries into the dated target version heading and leave a fresh `## [Unreleased]` section above it.
- GitHub Releases may use generated notes.
- Any release with breaking changes must include upgrade guides covering deployment and release steps for the new version.

## Workflow

1. Read the current release state.
2. Decide whether this is release preparation, stable release publication, or manual prerelease publication.
3. Confirm the explicit target tag and derive the unprefixed application version.
4. Align `mix.exs` and `CHANGELOG.md` with the target release.
5. Verify release metadata and Git state.
6. Execute the matching release path.
7. Report the exact tag, commit, release URL, release date, and workflow status.

## Preflight

Run:

```bash
git fetch --tags --prune
git status --short --branch
git tag --sort=-version:refname | sed -n '1,20p'
```

Rules:
- Inspect release state from any branch, but perform version edits and release publication from `main`.
- If the tree is dirty, stop and surface the changed files before continuing.
- Check whether the target tag or GitHub Release already exists before creating anything.

Use the helper script with the complete Git tag:

```bash
.agents/skills/save-it-release/scripts/check_release_state.sh v0.5.0
```

The helper validates the tag format, derives the unprefixed `mix.exs` version, and exits with an error if a non-`main` branch introduces, stages, or leaves an unstaged `mix.exs` version change.

## Release Preparation

When the user asks to prepare a release but not publish it yet:

1. Confirm the current branch is `main` and the target tag is explicit.
2. Remove the leading `v` when updating `mix.exs`:

```elixir
version: "0.5.0"
```

3. Roll `CHANGELOG.md` `Unreleased` entries into the target heading, with the date outside the tag:

```markdown
## [v0.5.0] - 2026-09-04
```

4. If the release page needs curated notes, prepare a short English draft for the GitHub Release body.
5. Show the diff for `mix.exs` and `CHANGELOG.md`.
6. Do not tag or publish unless the user explicitly asks to release.

## Stable Release Publication

When the user asks to publish a stable release:

1. Confirm the current branch is `main`, the unprefixed target version exists in `mix.exs`, and the target tag matches `vMAJOR.MINOR.PATCH`.
2. Confirm `CHANGELOG.md` has a dated heading for the complete target tag and a fresh `## [Unreleased]` heading above it.
3. Commit release metadata changes using the target tag as the message:

```bash
git add mix.exs CHANGELOG.md
git commit -m "v0.5.0"
```

4. Create and push the stable tag:

```bash
git tag -a v0.5.0 -m "v0.5.0"
git push origin main
git push origin refs/tags/v0.5.0
```

5. Publish the GitHub Release with the changelog date after the tag. Prefer generated notes unless the user already prepared custom notes:

```bash
release_date="YYYY-MM-DD" # Use the date from the matching changelog heading.
rg -n -F "## [v0.5.0] - $release_date" CHANGELOG.md
gh release create v0.5.0 \
  --verify-tag \
  --title "save_it v0.5.0 - $release_date" \
  --generate-notes
```

6. Check whether the `Release` workflow was triggered:

```bash
gh run list --limit 5
```

If the user wants more confidence before release, run the acceptance flow from `.agents/skills/acceptance-testing/SKILL.md`.

## Manual Prerelease Publication

When the user asks for a prerelease:

1. Confirm the current branch is `main` and use a tag such as `v0.5.0-rc.1`; keep `mix.exs` at `0.5.0-rc.1`.
2. Confirm `CHANGELOG.md` has a dated heading for the complete prerelease tag and a fresh `## [Unreleased]` heading above it.
3. Prefer the existing GitHub Actions workflow instead of manually crafting a prerelease:

```bash
gh workflow run "Release (manual)" -f tag=v0.5.0-rc.1
```

4. This workflow validates the tag, reads the release date from its changelog heading, publishes a GitHub prerelease with the same date in its title, strips `v` from the Docker image version, and triggers Docker publication with prerelease semantics.

## Guardrails

- Never publish a stable release from a dirty working tree.
- Never create a release if `mix.exs`, `CHANGELOG.md`, and the intended tag disagree on the version.
- Never include a date in a SemVer Git tag.
- Never put the `v` prefix in `mix.exs`.
- Never rename or recreate historical CalVer tags or GitHub Releases.
- Never publish a new unprefixed release tag.
- Never publish a release or prerelease without checking whether `CHANGELOG.md` needs a release rollover.
- Never recreate an existing tag or GitHub Release.
- Never use the manual prerelease workflow for a normal stable release when direct GitHub Release publication is intended.

## Acceptance Checklist

Before finishing, verify all items:

- [ ] Requirement is implemented end-to-end.
- [ ] Scope is minimal and aligned with project goal.
- [ ] Existing behavior is not unintentionally broken.
- [ ] Commands/tests needed for confidence were run, or skipped with reason.
- [ ] Relevant docs/checklists are updated if scope or constraints changed.
- [ ] Output is clear for direct handoff.

## Related Files

- `mix.exs`
- `CHANGELOG.md`
- `.github/workflows/release.yml`
- `.github/workflows/release-manual.yml`
- `.agents/skills/save-it-changelog/SKILL.md`
- `.agents/skills/acceptance-testing/SKILL.md`

## Resources

- `scripts/check_release_state.sh`
