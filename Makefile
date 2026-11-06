APP := .build/xcode/Build/Products/Release/NtfyMac.app
SWIFT_FILES := Sources tests App/Sources Package.swift
TOOLS := scripts/tools.sh
MACBOOK := iumac
MACBOOK_APP := Applications/NtfyMac.app
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

.PHONY: check toolchain format lint-format lint lint-sh analyze build test app snapshots package installer-check docs docs-check install-macbook

check: toolchain lint-format lint lint-sh build docs-check test installer-check app

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
	shellcheck install.sh scripts/*.sh

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

# Builds, signs and packages the release assets into dist/. The version must already be stamped into the
# tree (scripts/stamp-version.sh); package.sh refuses a CLI that reports another version.
package:
	@test -n "$(VERSION)" || { echo "usage: make package VERSION=x.y.z"; exit 1; }
	$(MAKE) app
	scripts/package.sh $(VERSION)

# install.sh against a fake release: temp HOME and dirs, no app build, no launch.
installer-check:
	scripts/test-install.sh

# Copies the ad-hoc-signed app to ~/Applications on the MacBook (ssh host $(MACBOOK)), quits the
# running copy and opens the new one, so the next thing the owner sees is this build.
install-macbook: app
	ssh -o BatchMode=yes $(MACBOOK) 'mkdir -p ~/Applications'
	rsync -a --delete -e 'ssh -o BatchMode=yes' $(APP)/ $(MACBOOK):$(MACBOOK_APP)/
	ssh -o BatchMode=yes $(MACBOOK) '$(LSREGISTER) -f ~/$(MACBOOK_APP) && \
		codesign --verify --deep --strict ~/$(MACBOOK_APP) && \
		echo "installed: $$HOME/$(MACBOOK_APP)" && \
		codesign -dv ~/$(MACBOOK_APP) 2>&1 | grep -E "^(Identifier|Signature|Format|CodeDirectory)"'
	ssh -o BatchMode=yes $(MACBOOK) 'pkill -x NtfyMac; sleep 1; open ~/$(MACBOOK_APP) && echo "relaunched: $$HOME/$(MACBOOK_APP)"'
