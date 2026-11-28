#!/usr/bin/env bash
# Exits 0 when everything this tree changed since the merge base with origin/master is prose that no build, lint or test
# reads: `make check-fast` then has nothing to compile. Anything else, an empty diff, an unknown base or a failing git
# call exits 1 (run the gate). The generated pages docs/cli.md and docs/settings.md are not prose here: docs-check
# compares them with the built CLI. CI never calls this; its gate is the full one.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
base="$(git merge-base HEAD origin/master 2>/dev/null || git merge-base HEAD master 2>/dev/null)" || exit 1

changed="$({ git diff --no-renames --name-only "$base"; git ls-files --others --exclude-standard; } | sort -u)"
[ -n "$changed" ] || exit 1

while IFS= read -r path; do
  case "$path" in
    docs/cli.md | docs/settings.md) exit 1 ;;
    docs/*.md | docs/plan.yaml | docs/images/*) ;;
    AGENTS.md | CHANGELOG.md | REVIEW.md | LICENSE) ;;
    *) exit 1 ;;
  esac
done <<< "$changed"
