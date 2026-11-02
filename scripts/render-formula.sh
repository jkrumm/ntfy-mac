#!/usr/bin/env bash
# Renders packaging/ntfy-mac.rb.in to stdout. The tap job redirects it over Formula/ntfy-mac.rb.
set -euo pipefail

version="${1:?usage: render-formula.sh <version> <sha256>}"
sha256="${2:?usage: render-formula.sh <version> <sha256>}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || { echo "not a semantic version: $version" >&2; exit 1; }
[[ "$sha256" =~ ^[0-9a-f]{64}$ ]] || { echo "not a sha256: $sha256" >&2; exit 1; }

sed -e "s|@VERSION@|$version|g" -e "s|@SHA256@|$sha256|g" "$root/packaging/ntfy-mac.rb.in"
