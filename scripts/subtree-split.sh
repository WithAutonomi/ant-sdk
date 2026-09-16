#!/usr/bin/env bash
# Split one monorepo subdirectory into a standalone commit chain with
# `git subtree split` and sanity-check the result.
#
# Used by the read-only mirror workflows (sync-php-mirror.yml, later Swift):
# Packagist and SwiftPM need the package manifest at the ROOT of the git
# repository they are pointed at, which a monorepo subdirectory cannot give
# them, so CI publishes each such SDK as its own mirror repository.
#
# `git subtree split` is deterministic: the same input history always yields
# the same split SHAs, so a split taken at a release tag is an ancestor of a
# later split taken at main, and repeated runs are idempotent.
#
# Usage: scripts/subtree-split.sh <prefix> [<ref>]
#   prefix  subdirectory to split, e.g. antd-php
#   ref     commit to split at (default HEAD)
# Prints the split commit SHA on stdout; everything else goes to stderr.
# Needs the full history (not a shallow clone).

set -euo pipefail

prefix="${1:?usage: $0 <prefix> [<ref>]}"
ref="${2:-HEAD}"
prefix="${prefix%/}"

if [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
  echo "refusing to split a shallow clone (checkout with fetch-depth: 0)" >&2
  exit 1
fi

commit="$(git rev-parse --verify --quiet "${ref}^{commit}")" || {
  echo "unknown ref: $ref" >&2
  exit 1
}

expected_tree="$(git rev-parse --verify --quiet "${commit}:${prefix}")" || {
  echo "no directory '$prefix' at $commit" >&2
  exit 1
}

# Progress goes to stderr; the SHA is the only thing on stdout.
split="$(git subtree split --prefix="$prefix" "$commit")"

actual_tree="$(git rev-parse "${split}^{tree}")"
if [ "$expected_tree" != "$actual_tree" ]; then
  echo "split tree $actual_tree != ${commit}:${prefix} tree $expected_tree" >&2
  exit 1
fi

echo "split $prefix @ ${commit:0:12} -> ${split:0:12} ($(git rev-list --count "$split") commits, tree ${actual_tree:0:12})" >&2
echo "$split"
