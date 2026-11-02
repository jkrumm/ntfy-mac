#!/usr/bin/env bash
# Single entry point for code signing. Ad-hoc by default; set SIGN_IDENTITY to switch.
set -euo pipefail

app="${1:?usage: sign.sh <path-to-app>}"
identity="${SIGN_IDENTITY:--}"

codesign --force --deep --sign "$identity" "$app"
codesign --verify --deep --strict "$app"
