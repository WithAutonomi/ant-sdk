#!/usr/bin/env bash
# Used by .github/workflows/security-audit.yml after a resolve step.
#
# Copies every lockfile the resolve step generated into resolved/, keeping
# its repo path, so the osv-scanner job can lay them back over a fresh
# checkout. Most are gitignored (pubspec.lock, composer.lock, Gemfile.lock);
# the rest are merely untracked (requirements.txt, gradle.lockfile,
# Package.resolved), so both listings are needed.
set -euo pipefail

names='(^|/)(pubspec\.lock|composer\.lock|Gemfile\.lock|requirements\.txt|gradle\.lockfile|Package\.resolved)$'
{
  git ls-files --others --ignored --exclude-standard | grep -E "$names" || true
  git ls-files --others --exclude-standard | grep -E "$names" || true
} | grep -v -E '(^|/)(\.build|build|node_modules)/' | sort -u > /tmp/locks.txt

if [ ! -s /tmp/locks.txt ]; then
  echo "::error::no lockfiles were generated"
  exit 1
fi

while read -r f; do
  mkdir -p "resolved/$(dirname "$f")"
  cp "$f" "resolved/$f"
done < /tmp/locks.txt

echo "Generated lockfiles:"
cat /tmp/locks.txt
