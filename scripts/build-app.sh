#!/usr/bin/env bash
# build-app.sh <derived-data-dir> [xcodebuild settings…] — the Release app build behind `make app` and `make snapshots`,
# shaped to stay under the step's 2 GiB peak budget (project.yaml `budgets.peak`, default). Run it from the repo root.
#
# Both halves compile GRDB with whole-module optimisation, one swift-frontend of 1.1 to 1.3 GiB (package targets ignore
# SWIFT_COMPILATION_MODE, and a lower thread count does not shrink it). So:
#
#   1. the bundled CLI is built first, not inside xcodebuild, where it ran on top of about 1 GiB of build service;
#      the app target's script phase then only copies it (CLI_PREBUILT=YES)
#   2. one job at a time in each half, outside CI (a hosted runner has the machine to itself); APP_JOBS=n overrides
#   3. no debug info: about 200 MiB of that frontend, for a dSYM no release asset carries. Optimisation is unchanged.
set -euo pipefail

derived="${1:?usage: build-app.sh <derived-data-dir> [xcodebuild settings…]}"
shift
if [ "${CI:-}" = true ]; then jobs="${APP_JOBS:-}"; else jobs="${APP_JOBS:-1}"; fi

# xcodebuild adds the app's own dependency (Sparkle) to the package's Package.resolved, which the checked-in file does
# not carry. Put the file back as it was, so a build never leaves the tree dirty.
pins="$(mktemp)"
cp Package.resolved "$pins"
trap 'cp "$pins" Package.resolved; rm -f "$pins"' EXIT

# The same scrubbed environment as the script phase in App/project.yml, which asks this build for its bin path.
env -u SDKROOT -u MACOSX_DEPLOYMENT_TARGET -u CC -u CXX -u LD -u LIBRARY_PATH \
  xcrun swift build ${jobs:+-j "$jobs"} -c release --arch arm64 --product ntfy-mac --scratch-path .build/cli -debug-info-format none

xcodebuild -project App/NtfyMac.xcodeproj -scheme NtfyMac -configuration Release -derivedDataPath "$derived" ${jobs:+-jobs "$jobs"} \
  CLI_PREBUILT=YES GCC_GENERATE_DEBUGGING_SYMBOLS=NO DEBUG_INFORMATION_FORMAT=dwarf "$@" build
