APP := .build/xcode/Build/Products/Release/NtfyMac.app
SWIFT_FILES := Sources tests App/Sources Package.swift
TOOLS := scripts/tools.sh

.PHONY: verify-signature check check-fast toolchain format lint-format lint lint-sh analyze build test app snapshots package installer-check docs docs-check install-macbook

check: toolchain lint-format lint lint-sh build docs-check test installer-check app

# The lead's tier (project.yaml `checks.fast`): everything `check` runs except the Release xcodebuild (`app`) and the
# installer test. CI runs the full `check` on the PR head.
check-fast: toolchain lint-format lint lint-sh build docs-check test

# Runs once, as the first step of `check`. Fails closed: an unparseable version is an error.
# The other targets skip it: Package.swift's tools version already rejects a Swift older than 6.2.
toolchain:
	@xcodebuild -version | head -1
	@swift --version 2>&1 | head -1
	@swift --version 2>&1 | sed -nE 's/.*Swift version ([0-9]+)\.([0-9]+).*/\1 \2/p' | head -1 | \
		awk '{ seen = 1; if ($$1 < 6 || ($$1 == 6 && $$2 < 2)) bad = 1 } \
			END { if (!seen) { print "cannot parse the Swift version"; exit 1 } \
			if (bad) { print "Swift >= 6.2 required"; exit 1 } }'

format:
	swift format --in-place -r $(SWIFT_FILES)

lint-format:
	swift format lint --strict -r $(SWIFT_FILES)

lint:
	$(TOOLS) --self-test
	"$$($(TOOLS) swiftlint)" lint --strict --no-cache

# Fails when shellcheck is missing: a skipped lint must never look like a pass.
lint-sh:
	@command -v shellcheck > /dev/null || { echo "shellcheck not found (brew install shellcheck)"; exit 1; }
	shellcheck install.sh scripts/*.sh scripts/clean-machine/*.sh

# Not part of `check` yet: joins once the tree is clean.
analyze:
	"$$($(TOOLS) periphery)" scan

build:
	swift build

test:
	swift test

# Regenerates docs/cli.md, docs/settings.md and llms.txt from the debug CLI's `schema --json`. Offline: temp config and
# data dirs, no app, no Keychain. `docs-check` writes to a temp dir and fails when the checked-in files differ.
DOCS_GEN := scripts/generate-cli-docs.swift
DOCS_SCHEMA = NTFY_MAC_CONFIG_DIR="$$tmp/config" NTFY_MAC_DATA_DIR="$$tmp/data" \
	"$$(swift build --show-bin-path)/ntfy-mac" schema --json > "$$tmp/schema.json"

docs: build
	@tmp=$$(mktemp -d) && trap 'rm -rf "$$tmp"' EXIT && $(DOCS_SCHEMA) && \
		swift $(DOCS_GEN) "$$tmp/schema.json"

docs-check: build
	@tmp=$$(mktemp -d) && trap 'rm -rf "$$tmp"' EXIT && $(DOCS_SCHEMA) && \
		swift $(DOCS_GEN) "$$tmp/schema.json" --out "$$tmp/out" > /dev/null && \
		diff -u docs/cli.md "$$tmp/out/docs/cli.md" && \
		diff -u docs/settings.md "$$tmp/out/docs/settings.md" && diff -u llms.txt "$$tmp/out/llms.txt" || \
		{ echo "docs are stale: run 'make docs' and commit the result"; exit 1; }

app:
	cd App && "$$(../$(TOOLS) xcodegen)" generate
	scripts/apple-slot.sh xcodebuild -project App/NtfyMac.xcodeproj -scheme NtfyMac -configuration Release \
		-derivedDataPath .build/xcode build
	scripts/sign.sh $(APP)
	test -x $(APP)/Contents/MacOS/ntfy-mac
	$(APP)/Contents/MacOS/ntfy-mac version

# UI snapshots: a review aid, not a test. A separate build of the app with the SNAPSHOT_HARNESS flag (its own
# derived-data path, so the release app never contains the harness) draws every window and the popover offscreen,
# in light and dark, into SNAP_DIR. Isolated: temp HOME, in-memory fixtures, no real config, Keychain, network,
# notifications or windows on screen.
SNAP_APP := .build/xcode-snap/Build/Products/Release/NtfyMac.app
SNAP_DIR ?= .build/snapshots

snapshots:
	cd App && "$$(../$(TOOLS) xcodegen)" generate
	scripts/apple-slot.sh xcodebuild -project App/NtfyMac.xcodeproj -scheme NtfyMac -configuration Release \
		-derivedDataPath .build/xcode-snap SWIFT_ACTIVE_COMPILATION_CONDITIONS='$$(inherited) SNAPSHOT_HARNESS' build
	scripts/sign.sh $(SNAP_APP)
	home=$$(mktemp -d) && trap 'rm -r "$$home"' EXIT && \
		HOME="$$home" CFFIXED_USER_HOME="$$home" $(SNAP_APP)/Contents/MacOS/NtfyMac --ui-snapshot "$(SNAP_DIR)"

# Checks an app's signature: make verify-signature [APP=path] [MODE=--developer-id|--release].
verify-signature:
	scripts/verify-signature.sh $(APP) $(MODE)

# Builds, signs and packages the release assets into dist/. The version must already be stamped into the
# tree (scripts/stamp-version.sh); package.sh refuses a CLI that reports another version. It also refuses an app
# that is not Developer ID signed, notarized and stapled: run it with SIGN_IDENTITY=developer-id NOTARIZE=1.
# ALLOW_ADHOC=1 skips that for local packaging tests (no appcast).
package:
	@test -n "$(VERSION)" || { echo "usage: make package VERSION=x.y.z"; exit 1; }
	$(MAKE) app
	scripts/package.sh $(VERSION)

# install.sh against a fake release: temp HOME and dirs, no app build, no launch.
installer-check:
	scripts/test-install.sh

# Installs the app into ~/Applications on the MacBook by pulling: the MacBook rsyncs the bundle from the mini, checks
# the signature, quits the running copy and opens the new one. The mini's iumac key runs a fixed verb list only, so
# the one MacBook-side command goes through ask-human.sh (one approval dialog, scripts/install-macbook.sh). The app
# is ad-hoc signed unless SIGN_IDENTITY=developer-id NOTARIZE=1 make install-macbook builds the Developer ID
# signed, notarized and stapled app (needs the team's credentials, see scripts/sign.sh).
install-macbook: app
	scripts/install-macbook.sh $(APP)
