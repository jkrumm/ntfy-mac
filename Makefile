APP := .build/xcode/Build/Products/Release/NtfyMac.app
SWIFT_FILES := Sources tests App/Sources Package.swift
TOOLS := scripts/tools.sh
MACBOOK := iumac
MACBOOK_APP := Applications/NtfyMac.app
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

.PHONY: check toolchain format lint-format lint analyze build test app legacy install-macbook

check: toolchain lint-format lint build test app legacy

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

# Not part of `check` yet: joins once the tree is clean.
analyze:
	"$$($(TOOLS) periphery)" scan

build:
	swift build

test:
	swift test

app:
	cd App && "$$(../$(TOOLS) xcodegen)" generate
	xcodebuild -project App/NtfyMac.xcodeproj -scheme NtfyMac -configuration Release \
		-derivedDataPath .build/xcode build
	scripts/sign.sh $(APP)
	test -x $(APP)/Contents/MacOS/ntfy-mac
	$(APP)/Contents/MacOS/ntfy-mac version

legacy:
	@if [ -d src ]; then bun run validate; fi

# Copies the ad-hoc-signed app to ~/Applications on the MacBook (ssh host $(MACBOOK)). Never launches it.
install-macbook: app
	ssh -o BatchMode=yes $(MACBOOK) 'mkdir -p ~/Applications'
	rsync -a --delete -e 'ssh -o BatchMode=yes' $(APP)/ $(MACBOOK):$(MACBOOK_APP)/
	ssh -o BatchMode=yes $(MACBOOK) '$(LSREGISTER) -f ~/$(MACBOOK_APP) && \
		codesign --verify --deep --strict ~/$(MACBOOK_APP) && \
		echo "installed: $$HOME/$(MACBOOK_APP)" && \
		codesign -dv ~/$(MACBOOK_APP) 2>&1 | grep -E "^(Identifier|Signature|Format|CodeDirectory)"'
