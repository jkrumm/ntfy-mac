#!/usr/bin/env bash
# Renders packaging/ntfy-mac.cask.rb.in to stdout. The tap job redirects it over Casks/ntfy-mac.rb.
# The sha256 is the one of NtfyMac-<version>.zip, the Sparkle archive (the app alone).
set -euo pipefail

version="${1:?usage: render-cask.sh <version> <sha256-of-the-zip>}"
sha256="${2:?usage: render-cask.sh <version> <sha256-of-the-zip>}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || { echo "not a semantic version: $version" >&2; exit 1; }
[[ "$sha256" =~ ^[0-9a-f]{64}$ ]] || { echo "not a sha256: $sha256" >&2; exit 1; }

sed -e "s|@VERSION@|$version|g" -e "s|@SHA256@|$sha256|g" "$root/packaging/ntfy-mac.cask.rb.in"
