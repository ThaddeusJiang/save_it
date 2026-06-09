---
name: save-it-release
description: Prepare, verify, and publish `save_it` releases by updating `mix.exs`, creating the release commit and tag, and publishing a GitHub release. Use when the user asks to cut a stable release, prepare a prerelease, or verify release readiness for this repository. This repository uses CalVer `YYYY.M.D` for stable releases and prerelease tags such as `YYYY.M.D-rc.N`.
---

# Save It Release

Use this skill when the task is specifically about the `save_it` release flow.

This repository uses:
- `mix.exs` `version` as the application version
- Versioning: CalVer `YYYY.M.D` for stable releases, where the last segment is the calendar day of month (for example `2026.5.25`), with git tags using the same value without a `v` prefix, and hotfix such as `YYYY.M.D-hotfix.N`
- git tags that match the version string directly, for example `2026.5.25`
- GitHub Release publication to trigger `.github/workflows/release.yml`
- The GitHub release page as the changelog surface for this project
- `.github/workflows/release-manual.yml` for manual releases

## Release Rules

- The bump version commit message must be exactly `version`.
- The release tag must be created on the bump version commit.
- GitHub Releases may use generated notes.
- Any release with breaking changes must include upgrade guides covering deployment and release steps for the new version.

## Workflow

1. Read the current release state.
2. Decide whether this is release preparation, stable release publication, or manual prerelease publication.
3. Align `mix.exs` and the target release tag.
4. Verify release metadata and git state.
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
.agents/skills/save-it-release/scripts/check_release_state.sh YYYY.M.D
```

## Release Preparation

When the user asks to prepare a release but not publish it yet:

1. Update `mix.exs`:

```elixir
version: "YYYY.M.D"
```

2. If the release page needs curated notes, prepare a short English draft for the GitHub release body.
3. Show the diff for `mix.exs`.
4. Do not tag or publish unless the user explicitly asks to release.

## Stable Release Publication

When the user asks to publish a stable release:

1. Confirm the released version exists in `mix.exs`.
2. Commit release metadata changes using the repository convention:

```bash
git add mix.exs
git commit -m "version"
```

3. Create and push the stable tag:

```bash
git tag -a YYYY.M.D -m "YYYY.M.D"
git push origin main
git push origin refs/tags/YYYY.M.D
```

4. Publish the GitHub release page entry. Prefer generated notes unless the user already prepared custom notes:

```bash
gh release create YYYY.M.D \
  --verify-tag \
  --title "save_it YYYY.M.D" \
  --generate-notes
```

5. Check whether the `Release` workflow was triggered:

```bash
gh run list --limit 5
```

If the user wants more confidence before release, run the acceptance flow from `.agents/skills/acceptance-testing/SKILL.md`.

## Manual Prerelease Publication

When the user asks for a prerelease:

1. Keep the version in the repository's CalVer prerelease form, for example `2026.5.25-rc.1`.
2. Prefer the existing GitHub Actions workflow instead of manually crafting a prerelease:

```bash
gh workflow run "Release (manual)" -f tag=YYYY.M.D-rc.N
```

3. This workflow publishes a GitHub prerelease and triggers Docker publish with prerelease semantics.

## Guardrails

- Never publish a stable release from a dirty working tree.
- Never create a stable release if `mix.exs` and the intended tag disagree on the version.
- Never interpret the final stable version segment as an incrementing monthly patch number; it is the calendar day of month for the release date.
- Never use a non-CalVer stable version format in this repository unless the project convention is explicitly changed again.
- Never add a `v` prefix to new release tags in this repository.
- Never pretend a repository changelog exists for this project. Use the GitHub release page instead.
- Never recreate an existing tag or GitHub release.
- Never use the manual prerelease workflow for a normal stable release when direct GitHub release publication is intended.

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
- `.github/workflows/release.yml`
- `.github/workflows/release-manual.yml`
- `.agents/skills/acceptance-testing/SKILL.md`

## Resources

- `scripts/check_release_state.sh`
