#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <version>" >&2
  exit 1
fi

version="$1"
tag="${version}"
branch="$(git branch --show-current)"

version_changed() {
  git diff --unified=0 "$@" -- mix.exs |
    rg --quiet '^[+-][[:space:]]*version:[[:space:]]*"'
}

if [ "$branch" != "main" ]; then
  if ! git rev-parse --verify origin/main >/dev/null 2>&1; then
    echo "error: origin/main is required to validate release branch state" >&2
    exit 1
  fi

  main_base="$(git merge-base origin/main HEAD)"

  if version_changed "$main_base" HEAD || version_changed --cached || version_changed; then
    echo "error: mix.exs version changes must be made directly on main" >&2
    echo "current branch: ${branch:-detached HEAD}" >&2
    exit 1
  fi
fi

echo "branch=${branch}"
echo "tag=${tag}"
echo "head=$(git rev-parse --short HEAD)"

echo
echo "[git status]"
git status --short --branch

echo
echo "[mix.exs version]"
rg -n "version:\\s*\"${version}\"" mix.exs || true

echo
echo "[local tag]"
git rev-parse --verify "${tag}" >/dev/null 2>&1 && echo "exists" || echo "missing"

echo
echo "[remote tag]"
git ls-remote --tags origin "refs/tags/${tag}" | sed '/^$/d' || true

echo
echo "[github release]"
gh release view "${tag}" --json url,isDraft,isPrerelease,publishedAt --jq '{url, isDraft, isPrerelease, publishedAt}' 2>/dev/null || echo "missing"
