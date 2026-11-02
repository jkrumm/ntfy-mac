#!/usr/bin/env bash
# Tests install.sh against a fake release (file:// base URL, temp HOME and dirs, no app build, no launch).
# The fake bundle's CLI is a script, so `migrate` is a stub that records its call.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
installer="$root/install.sh"
version="9.9.9"
archive="ntfy-mac-$version-arm64.tar.gz"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

passed=0
failed=0
ok() { passed=$((passed + 1)); echo "ok   $1"; }
bad() { failed=$((failed + 1)); echo "FAIL $1" >&2; }
check() { # description, command...
  local what="$1"
  shift
  if "$@"; then ok "$what"; else bad "$what"; fi
}

# make_release <dir> [extra file to add to the archive root]
make_release() {
  local dir="$1" extra="${2:-}"
  local src="$dir.src"
  mkdir -p "$dir" "$src/NtfyMac.app/Contents/MacOS"
  cat >"$src/NtfyMac.app/Contents/MacOS/ntfy-mac" <<'STUB'
#!/bin/sh
case "$1" in
  migrate) echo migrate >>"$(dirname "$0")/migrate.log" ;;
  version) echo "ntfy-mac 9.9.9" ;;
esac
STUB
  chmod +x "$src/NtfyMac.app/Contents/MacOS/ntfy-mac"
  echo license >"$src/LICENSE"
  if [[ -n "$extra" ]]; then echo x >"$src/$extra"; fi
  (cd "$src" && COPYFILE_DISABLE=1 tar --no-xattrs -czf "$dir/$archive" NtfyMac.app LICENSE ${extra:+"$extra"})
  (cd "$dir" && shasum -a 256 "$archive" >SHA256SUMS)
}

# run_install <case-dir> <release-dir>; leaves stdout/stderr in <case-dir>/out
run_install() {
  local c="$1" rel="$2"
  mkdir -p "$c/home"
  HOME="$c/home" NTFY_MAC_VERSION="$version" NTFY_MAC_BASE_URL="file://$rel" \
    NTFY_MAC_APP_DIR="$c/apps" NTFY_MAC_BIN_DIR="$c/bin" NTFY_MAC_NO_LAUNCH=1 \
    bash "$installer" >"$c/out" 2>&1
}

installed() { [[ -x "$1/apps/NtfyMac.app/Contents/MacOS/ntfy-mac" && -L "$1/bin/ntfy-mac" ]]; }
nothing_installed() { [[ ! -e "$1/apps/NtfyMac.app" && ! -e "$1/bin/ntfy-mac" ]]; }
no_leftovers() { ! compgen -G "$1/apps/.NtfyMac.app.*" >/dev/null; }
links_to_bundle() { [[ "$(readlink "$1/bin/ntfy-mac")" == "$1/apps/NtfyMac.app/Contents/MacOS/ntfy-mac" ]]; }
migrated() { [[ -f "$1/apps/NtfyMac.app/Contents/MacOS/migrate.log" ]]; }
runs() { [[ "$("$1/bin/ntfy-mac" version)" == "ntfy-mac 9.9.9" ]]; }

make_release "$tmp/good"

# happy path
c="$tmp/happy"
if run_install "$c" "$tmp/good"; then ok "happy path exits 0"; else bad "happy path exits 0"; cat "$c/out" >&2; fi
check "happy path installs bundle and symlink" installed "$c"
check "symlink targets the bundle CLI" links_to_bundle "$c"
check "migrate ran" migrated "$c"
check "symlink resolves to a working CLI" runs "$c"
check "no staging leftovers" no_leftovers "$c"

# rerun is idempotent
if run_install "$c" "$tmp/good"; then ok "rerun exits 0"; else bad "rerun exits 0"; cat "$c/out" >&2; fi
check "rerun keeps a working install" runs "$c"
check "rerun leaves no staging leftovers" no_leftovers "$c"

# 1.x binary replaced
c="$tmp/legacy"
mkdir -p "$c/bin"
printf '\xcf\xfa\xed\xfe legacy binary' >"$c/bin/ntfy-mac"
if run_install "$c" "$tmp/good"; then ok "1.x upgrade exits 0"; else bad "1.x upgrade exits 0"; cat "$c/out" >&2; fi
check "1.x regular binary replaced by the symlink" links_to_bundle "$c"

# tampered tarball fails closed
mkdir -p "$tmp/tampered"
cp "$tmp/good/"* "$tmp/tampered/"
echo tampered >>"$tmp/tampered/$archive"
c="$tmp/tampered-case"
if run_install "$c" "$tmp/tampered"; then bad "tampered tarball fails"; else ok "tampered tarball fails"; fi
check "tampered tarball installs nothing" nothing_installed "$c"
check "tampered failure mentions the checksum" grep -q "checksum" "$c/out"

# tampered tarball must not clobber an existing install
c="$tmp/tampered-upgrade"
run_install "$c" "$tmp/good" || bad "setup for upgrade-protection case"
if run_install "$c" "$tmp/tampered"; then bad "tampered upgrade fails"; else ok "tampered upgrade fails"; fi
check "tampered upgrade keeps the old install" runs "$c"

# missing SHA256SUMS
mkdir -p "$tmp/nosums"
cp "$tmp/good/$archive" "$tmp/nosums/"
c="$tmp/nosums-case"
if run_install "$c" "$tmp/nosums"; then bad "missing SHA256SUMS fails"; else ok "missing SHA256SUMS fails"; fi
check "missing SHA256SUMS installs nothing" nothing_installed "$c"

# SHA256SUMS without the archive
mkdir -p "$tmp/othersums"
cp "$tmp/good/$archive" "$tmp/othersums/"
echo "$(printf '0%.0s' {1..64})  other.tar.gz" >"$tmp/othersums/SHA256SUMS"
c="$tmp/othersums-case"
if run_install "$c" "$tmp/othersums"; then bad "SHA256SUMS without the archive fails"; else ok "SHA256SUMS without the archive fails"; fi
check "SHA256SUMS without the archive installs nothing" nothing_installed "$c"

# unexpected archive entry (correct checksum, wrong content)
make_release "$tmp/extra" "evil.txt"
c="$tmp/extra-case"
if run_install "$c" "$tmp/extra"; then bad "unexpected entry fails"; else ok "unexpected entry fails"; fi
check "unexpected entry installs nothing" nothing_installed "$c"
check "unexpected entry is named" grep -q "unexpected entry" "$c/out"

# bad version string
c="$tmp/badversion"
mkdir -p "$c/home"
if HOME="$c/home" NTFY_MAC_VERSION="../1.0" NTFY_MAC_BASE_URL="file://$tmp/good" NTFY_MAC_APP_DIR="$c/apps" \
  NTFY_MAC_BIN_DIR="$c/bin" NTFY_MAC_NO_LAUNCH=1 bash "$installer" >"$c/out" 2>&1; then
  bad "non-semver version fails"
else
  ok "non-semver version fails"
fi

echo "$passed passed, $failed failed"
[[ "$failed" -eq 0 ]]
