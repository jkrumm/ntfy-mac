#!/usr/bin/env bash
# Stamps a release version into the working tree: Version.swift and the app's Info.plist fields in
# App/project.yml. Used by the release build on the CI checkout; the committed tree keeps "-dev".
# Idempotent. The plist fields take the numeric core (x.y.z), the CLI string takes the full version.
set -euo pipefail

version="${1:?usage: stamp-version.sh <version>}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ! "$version" =~ ^([0-9]+\.[0-9]+\.[0-9]+)(-[0-9A-Za-z.-]+)?$ ]]; then
  echo "not a semantic version: $version" >&2
  exit 1
fi
core="${BASH_REMATCH[1]}"

swift_file="$root/Sources/NtfyCore/Version.swift"
project_file="$root/App/project.yml"

patch_file() { # file, sed expression, expected-after pattern
  local file="$1" expr="$2" check="$3" tmp
  tmp="$(mktemp)"
  sed -E "$expr" "$file" >"$tmp"
  if ! grep -Eq -- "$check" "$tmp"; then
    rm -f "$tmp"
    echo "no version field to stamp in $file" >&2
    exit 1
  fi
  cat "$tmp" >"$file"
  rm -f "$tmp"
}

patch_file "$swift_file" \
  "s|(static let current = )\"[^\"]*\"|\\1\"$version\"|" \
  "static let current = \"$version\""
patch_file "$project_file" \
  "s|(CFBundleShortVersionString: )\"[^\"]*\"|\\1\"$core\"|; s|(CFBundleVersion: )\"[^\"]*\"|\\1\"$core\"|" \
  "CFBundleShortVersionString: \"$core\""
grep -Eq "CFBundleVersion: \"$core\"" "$project_file" || {
  echo "no CFBundleVersion to stamp in $project_file" >&2
  exit 1
}
echo "stamped $version"
