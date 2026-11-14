---
# Read by the router (route.py) and by the reviewer. Globs are repo-relative.
none:        [docs/waves/**, docs/cli.md, docs/settings.md, llms.txt, CHANGELOG.md, Package.resolved]
sensitive:   [Sources/NtfyCore/ConfigTokenMigration.swift, Sources/NtfyCore/LegacyInstall*.swift,
              Sources/NtfyCore/TeamPin.swift, Sources/NtfyCore/UpdateStatus.swift,
              Sources/NtfyClient/URLSession*.swift, Sources/NtfyPlatform/KeychainSecretStore.swift,
              Sources/NtfyPlatform/FileConfigStore.swift, Sources/NtfyPlatform/LegacyInstallAdapters.swift,
              Sources/NtfyPlatform/CodeSigning.swift, Sources/NtfyMacCLI/MigrateCommand.swift,
              Sources/NtfyMacCLI/UpdateCommand.swift, App/Sources/SparkleUpdater.swift,
              Sources/NtfyIPC/**, Sources/NtfyStore/HistorySchema.swift, install.sh, packaging/**,
              scripts/sign.sh, scripts/package.sh, scripts/stamp-version.sh, scripts/render-cask.sh,
              .github/**, .releaserc.json]
nits: 3
---
# REVIEW.md — ntfy-mac

A public app on other people's Macs, so a bad change cannot be rolled back on a server. What failure looks like here:

- **The token leaks.** The token belongs in the Keychain. It goes only to the configured server's origin, over https unless
  `allowInsecure` is set: no redirects, no cross-origin attachment or image fetch with it, never in a log, a CLI output or an IPC
  reply.
- **An update bricks or weakens an install.** Sparkle (in the app only) verifies the EdDSA signature and the code signature and swaps
  the bundle; the app refuses to start it for a Homebrew copy, an unsigned build or another Team ID than the recorded one. `install.sh` stays checksum-verified, codesign-checked and atomic. A Homebrew install stays
  owned by Homebrew.
- **Migration eats user data.** `LegacyInstallCleanup` removes only the listed 1.x leftovers and never touches `config.json` or
  `state.json`. The AGENTS.md compatibility contract holds: config keys, env vars, every 1.x command and flag, the formula name, the
  priority table.
- **A notification is lost or doubled.** The cursor advances only after delivery is safe; catch-up, reconnect and boot reconcile
  must not replay or skip a message. A history schema change is a forward migration that keeps existing rows.
- **The architecture erodes.** `NtfyCore` depends on nothing and does no I/O; adapters see only the core; real adapters meet only in
  `App/Sources` and the CLI. Shared mutable state lives in actors; no singletons. A test goes through a module's interface.
- **The CLI contract drifts.** A command, flag or setting without its `CommandSpec` or `SettingsCatalog` row, an exit code changed
  outside `ErrorCatalog`, or a `schema --json` shape change without a `schemaVersion` bump. Agents script against these.
- **The IPC protocol breaks an older app.** New socket commands are additive and stay v1; an older app answers `bad-request`.
- **The public repo leaks.** The dev server's hostname, a token, an IP or a team id in any tracked file, fixture or doc.
- **The UI hangs the main actor.** Blocking file, database or network work on `@MainActor`, or a model with logic that a test cannot
  reach because it lives in `App/Sources` instead of `NtfyAppLogic`.

Skip: formatting, naming taste, lint-level remarks, test style. Evidence is always `file:line`.
