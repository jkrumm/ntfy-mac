# Contributing

## Prerequisites

- macOS on Apple Silicon with Xcode and Swift 6.2 or later
- `shellcheck` (`brew install shellcheck`) for the script lint in `make check`
- The pinned tools (SwiftLint, Periphery, XcodeGen) download into `.tools/` on first use, SHA-256 verified; do not install them with Homebrew

```bash
git clone https://github.com/jkrumm/ntfy-mac.git
cd ntfy-mac
```

## Workflow

```bash
make check            # the gate: format lint, SwiftLint, shellcheck, build, docs check, tests, installer test, app build
make check-fast       # the same without the app build and the installer test (no xcodebuild)
make format           # write swift format changes
make app              # build and ad-hoc sign NtfyMac.app into .build/xcode/Build/Products/Release
SIGN_IDENTITY=developer-id NOTARIZE=1 make app   # Developer ID, notarized and stapled (needs the team credentials)
make verify-signature APP=path MODE=--release    # check an app: signature, team, Hardened Runtime, ticket, Gatekeeper
make install-macbook  # (also with SIGN_IDENTITY=developer-id NOTARIZE=1) the MacBook pulls the app into ~/Applications (one ask-human approval dialog), then relaunches it
make analyze          # Periphery dead-code scan
make docs             # regenerate docs/cli.md, docs/settings.md and llms.txt from the CLI schema
```

`make check` is the full gate and CI runs it; `make check-fast` is the quick local tier. Never edit the generated docs by hand. A new command or setting needs a `CommandSpec` or `SettingsCatalog` entry first; `AGENTS.md` has the layout and the rules.

Commits follow [Conventional Commits](https://www.conventionalcommits.org). The `commit-msg` hook (lefthook, `scripts/check-commit-msg.sh`) checks the header and the 100-character line limit; CI runs commitlint with the conventional preset.

## Packaging

```bash
scripts/stamp-version.sh 2.0.0    # writes the version into Version.swift and App/project.yml (do not commit)
SIGN_IDENTITY=developer-id NOTARIZE=1 make package VERSION=2.0.0   # make app, then the files in dist/
make installer-check              # install.sh against a fake release in temp dirs
```

`make package` refuses a build whose CLI reports another version, so stamp first. The tarball holds `NtfyMac.app/` and `LICENSE`; the `LICENSE` sibling stops Homebrew from stripping a lone top-level `.app`. `dist/` holds the tarball, `NtfyMac-<version>.zip` (the app alone, the Sparkle enclosure), `appcast.xml` and `SHA256SUMS`. `make package` refuses an app that is not Developer ID signed, notarized and stapled, and checks that the staple ticket survives both archives; `ALLOW_ADHOC=1` is for local packaging tests only and writes no appcast.

All signing goes through `scripts/sign.sh`. The default is ad-hoc (`make check`, `make app`, snapshots, CI). `SIGN_IDENTITY=developer-id` signs with the team's Developer ID Application certificate, Hardened Runtime and a secure timestamp, and re-signs Sparkle's helpers inside out; `NOTARIZE=1` adds the Apple submission and the staple. If Apple does not answer within `NOTARY_TIMEOUT` (default 40m), the script prints the submission id: `RESUME_NOTARY_ID=<id> SIGN_IDENTITY=developer-id NOTARIZE=1 scripts/sign.sh <app>` waits on it without re-signing. `scripts/verify-signature.sh` runs at the end of every signing run and can be called alone. On the mini the credentials come from `secrets-run` (`op://mini/apple-developer`); elsewhere from `APPLE_TEAM_ID`, `ASC_KEY_P8`, `ASC_KEY_ID` and `ASC_ISSUER_ID`. The appcast is signed with the repo's Sparkle EdDSA key (`SPARKLE_ED_PRIVATE_KEY`, or `~/.local/state/apple-developer/sparkle-ntfy-mac-ed25519.key` on the mini); `scripts/tools.sh sparkle` pins the Sparkle tools.

`packaging/ntfy-mac.rb.in` is the Homebrew formula template; `scripts/render-formula.sh <version> <sha256>` fills it in.

## Release process

Releases run from the **Release** workflow (Actions, Run workflow). It is manual.

1. `make check` runs as a gate.
2. semantic-release reads the commits since the last tag and picks the version. Releasable types are `feat` (minor), `fix` and `perf` (patch); a `BREAKING CHANGE:` footer or `!` makes a major.
3. The exec plugin stamps the version, then builds, signs with the Developer ID, notarizes, staples and packages `dist/`. The workflow fails before this step when a signing secret is missing: `APPLE_TEAM_ID`, `APPLE_DEVELOPER_ID_P12_BASE64`, `APPLE_DEVELOPER_ID_P12_PASSWORD`, `ASC_KEY_P8`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `SPARKLE_ED_PRIVATE_KEY`.
4. The GitHub plugin creates a draft release, uploads the tarball, the zip, `appcast.xml` and `SHA256SUMS`, then publishes it, so the assets exist before the release is visible. `CHANGELOG.md` is committed back as `chore(release): <version>`.
5. The `tap` job downloads the published tarball, verifies it against `SHA256SUMS`, renders `Formula/ntfy-mac.rb` in `jkrumm/homebrew-tap`, runs `brew style` and pushes `chore(ntfy-mac): update to v<version>`.

`CHANGELOG.md` is written by semantic-release; do not edit it. Do not tag or publish by hand.
