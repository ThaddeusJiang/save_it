# Use Semantic Versioning for Releases

## Context and Problem Statement

The project adopted date-based CalVer release tags in 2026. Release dates are useful in the changelog and GitHub Release page, but encoding the date in the version makes the release sequence less familiar than conventional Semantic Versioning.

We need a release format that communicates compatibility through the version while keeping the publication date visible.

## Considered Options

* Continue using CalVer tags without a `v` prefix
* Return to `v`-prefixed Semantic Versioning tags and display the date separately
* Append the release date to a Semantic Versioning tag

## Decision Outcome

Chosen option: "Return to `v`-prefixed Semantic Versioning tags and display the date separately".

New releases use Git tags such as `v0.5.0` and prerelease tags such as `v0.5.0-rc.1`. The corresponding `mix.exs` version omits the `v` prefix. Changelog headings use `## [v0.5.0] - YYYY-MM-DD`, and GitHub Release titles use `save_it v0.5.0 - YYYY-MM-DD` with the same date.

Dates are display metadata and must not be appended to the Git tag. Historical CalVer releases and changelog headings remain unchanged.

This decision replaces the CalVer-specific parts of ADR 0003. ADR 0003 remains in effect for maintaining a curated Keep a Changelog file.

### Consequences

* Good, because versions follow a familiar compatibility-oriented format.
* Good, because release dates remain visible in both maintained release-note surfaces.
* Good, because historical tags do not need to be rewritten.
* Bad, because the first SemVer release after the CalVer period requires an explicit version choice rather than deriving a version from the date.
