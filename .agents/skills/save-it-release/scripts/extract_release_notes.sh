#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <version>" >&2
  exit 1
fi

version="$1"

awk -v version="$version" '
  $0 ~ "^## \\[" version "\\]" { in_section=1; next }
  in_section && /^## \[/ { exit }
  in_section { print }
' CHANGELOG.md
