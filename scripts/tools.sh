#!/usr/bin/env bash
# Pinned dev tools for macOS arm64: download, verify SHA-256, cache in .tools/, print the binary path.
# Usage: scripts/tools.sh <swiftlint|periphery|xcodegen|sparkle>
#        (sparkle prints bin/generate_appcast; sign_update sits in the same directory)
#        scripts/tools.sh --self-test   (proves a checksum mismatch is rejected)
# Bump a tool by changing its version and checksum below (checksum: `gh release view` asset digest).
# The tool variables are read through indirect expansion (${!var}), which shellcheck cannot follow.
# shellcheck disable=SC2034
set -euo pipefail

SWIFTLINT_VERSION="0.65.1"
SWIFTLINT_URL="https://github.com/realm/SwiftLint/releases/download/${SWIFTLINT_VERSION}/portable_swiftlint.zip"
SWIFTLINT_SHA256="c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0"
SWIFTLINT_BIN="swiftlint"

PERIPHERY_VERSION="3.8.0"
PERIPHERY_URL="https://github.com/peripheryapp/periphery/releases/download/${PERIPHERY_VERSION}/periphery-${PERIPHERY_VERSION}.zip"
PERIPHERY_SHA256="07d4e286e31dd79164df39097e0b59f533c94badbe18158464a455ea88a166d7"
PERIPHERY_BIN="periphery"

# XcodeGen finds its setting presets in ../share relative to the binary, so the tree stays intact.
XCODEGEN_VERSION="2.46.0"
XCODEGEN_URL="https://github.com/yonaskolb/XcodeGen/releases/download/${XCODEGEN_VERSION}/xcodegen.zip"
XCODEGEN_SHA256="4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806"
XCODEGEN_BIN="xcodegen/bin/xcodegen"

# Sparkle's release tools (generate_appcast, sign_update). The archive is a .tar.xz, the others are zips.
# Digest: `gh api repos/sparkle-project/Sparkle/releases/tags/<version>` (assets[].digest).
SPARKLE_VERSION="2.10.1"
SPARKLE_URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
SPARKLE_SHA256="1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27"
SPARKLE_BIN="bin/generate_appcast"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# fetch <url> <sha256> <dest-dir> <relative-binary>: leaves <dest-dir> populated or fails.
fetch() {
  local url="$1" sha="$2" dest="$3" rel="$4"
  # A subshell scopes the cleanup trap to this call; a RETURN trap would leak into later functions.
  (
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    curl --fail --silent --show-error --location --retry 3 --max-time 300 "$url" \
      --output "$work/archive"
    actual=$(shasum -a 256 "$work/archive" | cut -d' ' -f1)
    if [[ "$actual" != "$sha" ]]; then
      echo "checksum mismatch: expected $sha, got $actual" >&2
      exit 1
    fi
    mkdir -p "$work/out"
    case "$url" in
      *.tar.xz) tar -xJf "$work/archive" -C "$work/out" ;;
      *) unzip -q "$work/archive" -d "$work/out" ;;
    esac
    chmod +x "$work/out/$rel"
    rm -rf "$dest"
    mkdir -p "$(dirname "$dest")"
    mv "$work/out" "$dest"
  )
}

self_test() {
  local good
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  mkdir "$work/src"
  printf '#!/bin/sh\n' >"$work/src/tool"
  (cd "$work/src" && zip -q "$work/tool.zip" tool)
  good=$(shasum -a 256 "$work/tool.zip" | cut -d' ' -f1)
  if fetch "file://$work/tool.zip" "$(printf '0%.0s' {1..64})" "$work/bad" tool 2>/dev/null; then
    echo "self-test failed: a wrong checksum was accepted" >&2
    exit 1
  fi
  [[ ! -e "$work/bad" ]] || { echo "self-test failed: rejected archive was installed" >&2; exit 1; }
  fetch "file://$work/tool.zip" "$good" "$work/good" tool
  [[ -x "$work/good/tool" ]] || { echo "self-test failed: valid archive not installed" >&2; exit 1; }
  echo "tools.sh self-test ok"
}

tool="${1:?usage: tools.sh <swiftlint|periphery|xcodegen|sparkle|--self-test>}"

if [[ "$tool" == "--self-test" ]]; then
  (self_test)
  exit 0
fi

if [[ "$(uname -s)-$(uname -m)" != "Darwin-arm64" ]]; then
  echo "tools.sh supports macOS arm64 only" >&2
  exit 1
fi

case "$tool" in
  swiftlint | periphery | xcodegen | sparkle) ;;
  *)
    echo "unknown tool: $tool" >&2
    exit 1
    ;;
esac

upper=$(echo "$tool" | tr '[:lower:]' '[:upper:]')
version_var="${upper}_VERSION"
url_var="${upper}_URL"
sha_var="${upper}_SHA256"
bin_var="${upper}_BIN"
version="${!version_var}"
dest="$root/.tools/$tool-$version"
bin="$dest/${!bin_var}"

if [[ ! -x "$bin" ]]; then
  echo "fetching $tool $version" >&2
  fetch "${!url_var}" "${!sha_var}" "$dest" "${!bin_var}" >&2
fi
echo "$bin"
