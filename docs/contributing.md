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
make format           # write swift format changes
make app              # build and ad-hoc sign NtfyMac.app into .build/xcode/Build/Products/Release
make install-macbook  # copy the signed app to ~/Applications on the MacBook (ssh host iumac), never launches it
make analyze          # Periphery dead-code scan
make docs             # regenerate docs/cli.md, docs/settings.md and llms.txt from the CLI schema
```

`make check` is the single gate and CI runs the same target. Never edit the generated docs by hand. A new command or setting needs a `CommandSpec` or `SettingsCatalog` entry first; `AGENTS.md` has the layout and the rules.

Commits follow [Conventional Commits](https://www.conventionalcommits.org). The `commit-msg` hook (lefthook, `scripts/check-commit-msg.sh`) checks the header and the 100-character line limit; CI runs commitlint with the conventional preset.

## Packaging

```bash
scripts/stamp-version.sh 2.0.0    # writes the version into Version.swift and App/project.yml (do not commit)
make package VERSION=2.0.0        # make app, then dist/ntfy-mac-2.0.0-arm64.tar.gz and dist/SHA256SUMS
make installer-check              # install.sh against a fake release in temp dirs
```

`make package` refuses a build whose CLI reports another version, so stamp first. The tarball holds `NtfyMac.app/` and `LICENSE`; the `LICENSE` sibling stops Homebrew from stripping a lone top-level `.app`. All signing goes through `scripts/sign.sh`; set `SIGN_IDENTITY` to switch from ad-hoc to a real identity.

`packaging/ntfy-mac.rb.in` is the Homebrew formula template; `scripts/render-formula.sh <version> <sha256>` fills it in.

## Release process

Releases run from the **Release** workflow (Actions, Run workflow). It is manual.

1. `make check` runs as a gate.
2. semantic-release reads the commits since the last tag and picks the version. Releasable types are `feat` (minor), `fix` and `perf` (patch); a `BREAKING CHANGE:` footer or `!` makes a major.
3. The exec plugin stamps the version, then builds, signs and packages `dist/`.
4. The GitHub plugin creates a draft release, uploads the tarball and `SHA256SUMS`, then publishes it, so the assets exist before the release is visible. `CHANGELOG.md` is committed back as `chore(release): <version>`.
5. The `tap` job downloads the published tarball, verifies it against `SHA256SUMS`, renders `Formula/ntfy-mac.rb` in `jkrumm/homebrew-tap`, runs `brew style` and pushes `chore(ntfy-mac): update to v<version>`.

`CHANGELOG.md` is written by semantic-release; do not edit it. Do not tag or publish by hand.
