# [1.5.0](https://github.com/jkrumm/ntfy-mac/compare/v1.4.0...v1.5.0) (2026-03-20)


### Bug Fixes

* harden edge cases across notification pipeline ([9057e34](https://github.com/jkrumm/ntfy-mac/commit/9057e340b754953e94a28ed04d5201cee1e5c628))


### Features

* **notify:** map NTFY message fields to macOS notification capabilities ([accef70](https://github.com/jkrumm/ntfy-mac/commit/accef70df609aaaac460be9734bff69846c5e076))
* **notify:** migrate from osascript to Swift UserNotifications helper ([0f0c649](https://github.com/jkrumm/ntfy-mac/commit/0f0c6494664b28fe101fa01d57842b66d1da9066))
* **setup:** improve UX and notification permission prompt ([ac7bb91](https://github.com/jkrumm/ntfy-mac/commit/ac7bb91e9d4f501f286d836d6cda90e6203b9770))

# [1.4.0](https://github.com/jkrumm/ntfy-mac/compare/v1.3.1...v1.4.0) (2026-03-20)


### Features

* **notify:** use official gemoji emoji mappings for tags ([313eeb0](https://github.com/jkrumm/ntfy-mac/commit/313eeb05e627e878c37c1a37f73c79426ea36b84))

## [1.3.1](https://github.com/jkrumm/ntfy-mac/compare/v1.3.0...v1.3.1) (2026-03-20)


### Bug Fixes

* **notify:** rate-limit setup notification to once per hour ([67f9b42](https://github.com/jkrumm/ntfy-mac/commit/67f9b4272eb1763bd3413dae0b01aa031d7e0103))
* **setup:** use brew services restart instead of start ([9adcdec](https://github.com/jkrumm/ntfy-mac/commit/9adcdecf720ae012951f7a252cc0caa812f7e251))

# [1.3.0](https://github.com/jkrumm/ntfy-mac/compare/v1.2.0...v1.3.0) (2026-03-20)


### Bug Fixes

* **ci:** use RELEASE_TOKEN for semantic-release to bypass branch protection ([e02dd0d](https://github.com/jkrumm/ntfy-mac/commit/e02dd0dc632c5946ee2d6e12cd2b82c2b57cde29))
* **cli:** guard uninstall against dev mode execution ([1366486](https://github.com/jkrumm/ntfy-mac/commit/13664869c004218637f67f8d72a8adc1b493fdfc))
* **config:** use os.homedir() and atomic write permissions ([50ca5f5](https://github.com/jkrumm/ntfy-mac/commit/50ca5f5f3a911dc0e68dc14d89201223b0eeb259))


### Features

* **cli:** add ntfy-mac uninstall command ([b7799e7](https://github.com/jkrumm/ntfy-mac/commit/b7799e7aba66473635324ecbe7cbea4fc974333d))

# [1.2.0](https://github.com/jkrumm/ntfy-mac/compare/v1.1.0...v1.2.0) (2026-03-20)


### Features

* **setup:** auto-start brew service after successful setup ([ad6feb3](https://github.com/jkrumm/ntfy-mac/commit/ad6feb3e43cd154e5f9ad33e85e408eb5bf7c0b4))

# [1.1.0](https://github.com/jkrumm/ntfy-mac/compare/v1.0.0...v1.1.0) (2026-03-20)


### Features

* add curl install script with auto-update support ([f0eac2e](https://github.com/jkrumm/ntfy-mac/commit/f0eac2ef8066610a962c46077c9a68970446791e))

# 1.0.0 (2026-03-19)


### Bug Fixes

* address CodeRabbit findings and improve test coverage ([11fe467](https://github.com/jkrumm/homebrew-ntfy-mac/commit/11fe467764a0beb5bc2045da6c1f1d461f00d4f4))
* **ci:** fix semantic-release action version and add PR validation ([e86f1b1](https://github.com/jkrumm/homebrew-ntfy-mac/commit/e86f1b1d6df0fd1ada920be1c7cb773d875514e5))
* **ntfy:** fix SSE URL format, dedup race, and silent osascript errors ([ae252bc](https://github.com/jkrumm/homebrew-ntfy-mac/commit/ae252bc1c1d50e518e592df4680b17589f8f0e0f))
* **ntfy:** raise failure alert threshold and guard startup network error ([2770c36](https://github.com/jkrumm/homebrew-ntfy-mac/commit/2770c365095dcbef59ead3b56862387717d763b9))
* **runtime:** harden dedup, notify, and setup edge cases ([9b57133](https://github.com/jkrumm/homebrew-ntfy-mac/commit/9b571333e87c61c58258256fed755b8a31004698))
* **setup:** error on partial flags instead of falling back to interactive ([8e562e7](https://github.com/jkrumm/homebrew-ntfy-mac/commit/8e562e7ee391c19842bbec839e6727591c2a6fa4))


### Features

* **config:** add types and config loader with Keychain fallback ([5851911](https://github.com/jkrumm/homebrew-ntfy-mac/commit/585191157085688fdda97f7fcee3efc1b7c38544))
* **debug:** add NTFY_DEBUG=1 env var for verbose logging ([30ea6c0](https://github.com/jkrumm/homebrew-ntfy-mac/commit/30ea6c01fb0bf67079528bc03e3169445d5d32be))
* **dedup:** add state persistence with deduplication and cleanup ([63162cf](https://github.com/jkrumm/homebrew-ntfy-mac/commit/63162cf04f07acc0dbf5d632952c64c7720e46eb))
* **formula:** add Homebrew tap formula and fix release workflow ([1efbc8d](https://github.com/jkrumm/homebrew-ntfy-mac/commit/1efbc8de8858db42afc0556b60cb5a08300baf9a))
* **index:** add entry point with update check and daemon loop ([cb05a65](https://github.com/jkrumm/homebrew-ntfy-mac/commit/cb05a6597c43d29304759f483b779671f060b22b))
* **logs:** add ntfy-mac logs command and update README ([30da78f](https://github.com/jkrumm/homebrew-ntfy-mac/commit/30da78f029fb955c2bacc45d1151604c0c05d594))
* **notify:** add macOS notification delivery via osascript ([7f05cef](https://github.com/jkrumm/homebrew-ntfy-mac/commit/7f05cef32b62add85d1bd9ba69d5323137d452c0))
* **ntfy:** add connection failure alert and clean up logging ([31879ae](https://github.com/jkrumm/homebrew-ntfy-mac/commit/31879aeed1e2209fc12bda215fc879d7b2c1aca2))
* **ntfy:** add SSE listener, polling fallback, and topic discovery ([088188d](https://github.com/jkrumm/homebrew-ntfy-mac/commit/088188d04b2df48ef4a33184e807beea527aa1b8))
* **ntfy:** improve logging and add keepalive stall detection ([bb06097](https://github.com/jkrumm/homebrew-ntfy-mac/commit/bb0609714abe5b473da3d72843fdfc4220474728))
* **ntfy:** network-aware reconnect, poll_request handling, alert cooldown ([aa216bd](https://github.com/jkrumm/homebrew-ntfy-mac/commit/aa216bd86123bd75792af1d894d6daabac87fc61))
* **setup:** add interactive CLI setup wizard ([02a5a7c](https://github.com/jkrumm/homebrew-ntfy-mac/commit/02a5a7c398a8a570399ba73d67878675fb1dadb5))
* **setup:** improve UX and add non-interactive mode ([4aab780](https://github.com/jkrumm/homebrew-ntfy-mac/commit/4aab78013df88b65940d690e43af57e7d82f9a3b))

# Changelog

All notable changes to this project will be documented in this file. See [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) for commit guidelines.

This file is auto-generated by [semantic-release](https://github.com/semantic-release/semantic-release).
