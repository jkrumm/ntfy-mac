#!/usr/bin/env bash
# Tests install.sh against a fake release (file:// base URL, temp HOME and dirs, no app build, no launch).
# The fake bundle's CLI is a script, so `migrate` is a stub that records its call. The bundle is
# really signed (ad-hoc), so the installer's codesign check runs for real.
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

# make_release <dir> [extra file to add to the archive root] [mode]
# mode: failmigrate (the stub's migrate exits 1), unsigned, tampered (changed after signing),
#       outlink (a signed symlink to /etc), inlink (a signed symlink inside the bundle)
make_release() {
  local dir="$1" extra="${2:-}" mode="${3:-}"
  local src="$dir.src" app="$dir.src/NtfyMac.app"
  mkdir -p "$dir" "$app/Contents/MacOS" "$app/Contents/Resources"
  cat >"$app/Contents/MacOS/ntfy-mac" <<'STUB'
#!/bin/sh
here="$(dirname "$0")"
case "$1" in
  migrate)
    echo "bin_is_link=$([ -L "$NTFY_MAC_BIN_DIR/ntfy-mac" ] && echo yes || echo no) via=$0" >>"$here/migrate.log"
    [ ! -e "$here/../Resources/migrate.fail" ] || exit 1
    ;;
  version) echo "ntfy-mac 9.9.9" ;;
esac
STUB
  chmod +x "$app/Contents/MacOS/ntfy-mac"
  cat >"$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.jkrumm.ntfy-mac</string>
<key>CFBundleExecutable</key><string>ntfy-mac</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
  [[ "$mode" != failmigrate ]] || : >"$app/Contents/Resources/migrate.fail"
  [[ "$mode" != outlink ]] || ln -s /etc "$app/Contents/Resources/escape"
  [[ "$mode" != inlink ]] || ln -s ../MacOS/ntfy-mac "$app/Contents/Resources/inside"
  [[ "$mode" == unsigned ]] || codesign --force -s - "$app" >/dev/null 2>&1
  [[ "$mode" != tampered ]] || echo "# changed after signing" >>"$app/Contents/MacOS/ntfy-mac"
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
    NTFY_MAC_BREW_PREFIXES="${brew_prefixes:-$c/no-brew}" \
    bash "$installer" >"$c/out" 2>&1
}

installed() { [[ -x "$1/apps/NtfyMac.app/Contents/MacOS/ntfy-mac" && -L "$1/bin/ntfy-mac" ]]; }
nothing_installed() { [[ ! -e "$1/apps/NtfyMac.app" && ! -e "$1/bin/ntfy-mac" ]]; }
no_leftovers() { ! compgen -G "$1/apps/.NtfyMac.app.*" >/dev/null; }
links_to_bundle() { [[ "$(readlink "$1/bin/ntfy-mac")" == "$1/apps/NtfyMac.app/Contents/MacOS/ntfy-mac" ]]; }
migrated() { [[ -f "$1/apps/NtfyMac.app/Contents/MacOS/migrate.log" ]]; }
migrate_log() { head -1 "$1/apps/NtfyMac.app/Contents/MacOS/migrate.log"; }
migrated_before_relink() { [[ "$(migrate_log "$1")" == "bin_is_link=no via=$1/apps/NtfyMac.app/Contents/MacOS/ntfy-mac" ]]; }
runs() { [[ "$("$1/bin/ntfy-mac" version)" == "ntfy-mac 9.9.9" ]]; }

make_release "$tmp/good"

# happy path
c="$tmp/happy"
if run_install "$c" "$tmp/good"; then ok "happy path exits 0"; else bad "happy path exits 0"; cat "$c/out" >&2; fi
check "happy path installs bundle and symlink" installed "$c"
check "symlink targets the bundle CLI" links_to_bundle "$c"
check "migrate ran" migrated "$c"
check "migrate ran via the bundle path before the link existed" migrated_before_relink "$c"
check "symlink resolves to a working CLI" runs "$c"
check "no staging leftovers" no_leftovers "$c"

# a Homebrew copy blocks the install; without one nothing changes
c="$tmp/brew-case"
mkdir -p "$c/brew-a" "$c/brew-b/opt/ntfy-mac/NtfyMac.app"
if brew_prefixes="$c/brew-a:$c/brew-b" run_install "$c" "$tmp/good"; then bad "Homebrew copy refuses the install"; else ok "Homebrew copy refuses the install"; fi
check "Homebrew refusal installs nothing" nothing_installed "$c"
check "Homebrew refusal names brew upgrade" grep -q "brew upgrade ntfy-mac" "$c/out"
check "Homebrew refusal names brew uninstall" grep -q "brew uninstall ntfy-mac" "$c/out"
c="$tmp/brew-absent"
if brew_prefixes="$c/brew-a:$c/brew-b" run_install "$c" "$tmp/good"; then ok "no Homebrew copy installs as before"; else bad "no Homebrew copy installs as before"; cat "$c/out" >&2; fi
check "no Homebrew copy leaves a working install" runs "$c"

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
check "1.x upgrade migrates before the relink" migrated_before_relink "$c"

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

# a failing migrate is visible but does not undo the install
make_release "$tmp/failmigrate" "" failmigrate
c="$tmp/failmigrate-case"
if run_install "$c" "$tmp/failmigrate"; then ok "failing migrate still exits 0"; else bad "failing migrate still exits 0"; cat "$c/out" >&2; fi
check "failing migrate leaves the install in place" installed "$c"
check "failing migrate is reported" grep -q "warning: 'migrate' failed" "$c/out"

# a signed bundle with a link inside itself installs
make_release "$tmp/inlink" "" inlink
c="$tmp/inlink-case"
if run_install "$c" "$tmp/inlink"; then ok "link inside the bundle is accepted"; else bad "link inside the bundle is accepted"; cat "$c/out" >&2; fi

# a symlink that leaves the bundle
make_release "$tmp/outlink" "" outlink
c="$tmp/outlink-case"
if run_install "$c" "$tmp/outlink"; then bad "escaping symlink fails"; else ok "escaping symlink fails"; fi
check "escaping symlink installs nothing" nothing_installed "$c"
check "escaping symlink is named" grep -q "points outside the app" "$c/out"

# bad or missing code signature
for mode in unsigned tampered; do
  make_release "$tmp/$mode" "" "$mode"
  c="$tmp/$mode-case"
  if run_install "$c" "$tmp/$mode"; then bad "$mode bundle fails"; else ok "$mode bundle fails"; fi
  check "$mode bundle installs nothing" nothing_installed "$c"
  check "$mode failure mentions the code signature" grep -q "code signature" "$c/out"
done

# NTFY_MAC_BASE_URL is only honoured for file:// and local http://
for url in "https://evil.example/releases" "http://evil.example/x" "http://127.0.0.1.evil.example/x" "ftp://127.0.0.1/x"; do
  c="$tmp/baseurl-$(echo "$url" | tr -c 'A-Za-z0-9\n' _)"
  mkdir -p "$c/home"
  if HOME="$c/home" NTFY_MAC_VERSION="$version" NTFY_MAC_BASE_URL="$url" NTFY_MAC_APP_DIR="$c/apps" \
    NTFY_MAC_BIN_DIR="$c/bin" NTFY_MAC_NO_LAUNCH=1 bash "$installer" >"$c/out" 2>&1; then
    bad "base URL $url is refused"
  else
    ok "base URL $url is refused"
  fi
  check "base URL $url refusal says why" grep -q "NTFY_MAC_BASE_URL must be" "$c/out"
  check "base URL $url installs nothing" nothing_installed "$c"
done
for url in "http://127.0.0.1:1/x" "http://localhost/x"; do
  c="$tmp/baseok-$(echo "$url" | tr -c 'A-Za-z0-9\n' _)"
  mkdir -p "$c/home"
  HOME="$c/home" NTFY_MAC_VERSION="$version" NTFY_MAC_BASE_URL="$url" NTFY_MAC_APP_DIR="$c/apps" \
    NTFY_MAC_BIN_DIR="$c/bin" NTFY_MAC_NO_LAUNCH=1 bash "$installer" >"$c/out" 2>&1 || true
  check "base URL $url is accepted (fails later, at the download)" grep -q "download of" "$c/out"
done

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
