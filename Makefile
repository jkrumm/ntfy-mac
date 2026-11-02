APP := .build/xcode/Build/Products/Release/NtfyMac.app
SWIFT_FILES := Sources tests App/Sources Package.swift

.PHONY: check toolchain fmt fmt-check build test app legacy

check: fmt-check build test app legacy

toolchain:
	@xcodebuild -version | head -1
	@swift --version 2>&1 | head -1
	@swift --version 2>&1 | sed -nE 's/.*Swift version ([0-9]+)\.([0-9]+).*/\1 \2/p' | \
		awk '{ if ($$1 < 6 || ($$1 == 6 && $$2 < 2)) { print "Swift >= 6.2 required"; exit 1 } }'

fmt:
	xcrun swift-format format --in-place -r $(SWIFT_FILES)

fmt-check:
	xcrun swift-format lint --strict -r $(SWIFT_FILES)

build: toolchain
	swift build

test: toolchain
	swift test

app: toolchain
	cd App && xcodegen generate
	xcodebuild -project App/NtfyMac.xcodeproj -scheme NtfyMac -configuration Release \
		-derivedDataPath .build/xcode build
	scripts/sign.sh $(APP)
	test -x $(APP)/Contents/MacOS/ntfy-mac
	$(APP)/Contents/MacOS/ntfy-mac version

legacy:
	@if [ -d src ]; then bun run validate; fi
