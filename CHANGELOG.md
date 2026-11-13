# [2.0.0](https://github.com/jkrumm/ntfy-mac/compare/v1.11.0...v2.0.0) (2026-11-13)


* chore(legacy)!: remove the 1.x Bun daemon and Swift helper ([5b262c6](https://github.com/jkrumm/ntfy-mac/commit/5b262c6079b707e0135a569801b44873f2f0ff1d))


### Bug Fixes

* **app:** keep the History detail pane at full height when it is empty ([bc72dc8](https://github.com/jkrumm/ntfy-mac/commit/bc72dc89b8e3edba0ad78f2f0b059b698fa64261))
* **app:** remove the Homebrew 7 service sh.brew.ntfy-mac during migration ([d251927](https://github.com/jkrumm/ntfy-mac/commit/d251927279e90ef01355cb511cd8e11ad7cc5eb6))
* **app:** review fixes for login item, safe save-as, server save order, export and settings ordering ([38e6f7a](https://github.com/jkrumm/ntfy-mac/commit/38e6f7ae615b7d290b993184d79d123886ca3e6b))
* **app:** serialize poster categories, keep pipeline on config errors, guard lifecycle ([b88762c](https://github.com/jkrumm/ntfy-mac/commit/b88762cf43b35454a98938fd6340390a1b87f233))
* **app:** size snapshot windows by their content area ([3de7030](https://github.com/jkrumm/ntfy-mac/commit/3de7030741babca7ea23b021ee6c1fc2a69766d0))
* **client:** check HTTP status, refuse redirects, skip bad lines, validate topics ([80c0850](https://github.com/jkrumm/ntfy-mac/commit/80c0850cadc0b7a4f0724aa109e0061ae9dce68c))
* **client:** refuse redirects without a cooperative-pool hop ([7f5098f](https://github.com/jkrumm/ntfy-mac/commit/7f5098f54f065be8a5ea4aea29296f55bee841c9))
* **client:** resume a cancelled attachment download exactly once, tidy rollback and staging ([97841bb](https://github.com/jkrumm/ntfy-mac/commit/97841bb4ee7ec9156033bc7657e98e5e61fce28f))
* **cli:** fail closed on unreadable archive listings and harden migration and swap ([26619d5](https://github.com/jkrumm/ntfy-mac/commit/26619d56a1fc33524e337deb9d36cb15f5a7164e))
* **core:** keep reminders until shown, page boot reconcile, check resolved hosts ([763bea6](https://github.com/jkrumm/ntfy-mac/commit/763bea6228d0813c4b0358b1be34c46d9f02ab61))
* **history:** keep the detail actions in place when acknowledging ([d3e1386](https://github.com/jkrumm/ntfy-mac/commit/d3e1386af1751ba48bc3c7bf4e646d070ea030cc))
* **history:** read the acknowledge threshold before building the list query ([219a2fd](https://github.com/jkrumm/ntfy-mac/commit/219a2fd2048db900caf9aa831a92c99ba30737fb))
* **installer:** migrate before relinking, restrict the test base URL, verify the bundle ([24dd6fb](https://github.com/jkrumm/ntfy-mac/commit/24dd6fb77c6e407e12e61bbbe6877bf9e1f5fb73))
* **ipc:** serve local notify without a server, validate payloads, harden the socket server ([312e86d](https://github.com/jkrumm/ntfy-mac/commit/312e86d585f0de953aa6418fb51998fef43d97ac))
* **meeting:** close the hold race, timed presenting default, unknown audio reads and boot reading ([81e4b35](https://github.com/jkrumm/ntfy-mac/commit/81e4b356db98347ba7e90caa49244adac4f7d0a6))
* **update:** join a running Sparkle check and pin the framework version ([91fc8bf](https://github.com/jkrumm/ntfy-mac/commit/91fc8bff620cd5e8ac369d92342d8509aa94ae07))
* **window:** reopening the running app fronts the open window or opens History ([b285d50](https://github.com/jkrumm/ntfy-mac/commit/b285d50889905c5c6358ce9a46da524d54d236b5))


### Features

* **app-logic:** chat thread model with conversations, day groups, read-on-scroll and composer ([e02aabe](https://github.com/jkrumm/ntfy-mac/commit/e02aabe3d1507c83a186597ce5446bd16bff9a8f))
* **app:** add MenuRow with a native hover highlight for popover rows ([0f954bb](https://github.com/jkrumm/ntfy-mac/commit/0f954bba6fbaacd5468e8983441dccafcd9628fb))
* **app:** chat-style history window with per-topic conversations and a composer ([7d59b3b](https://github.com/jkrumm/ntfy-mac/commit/7d59b3b5d43fdbbb5a2091ef641b4fbc25690610))
* **app:** clean up 1.x install artifacts on first run and add ntfy-mac migrate ([3c2f568](https://github.com/jkrumm/ntfy-mac/commit/3c2f5689634e388b86c4913d47efa1e61df54a43))
* **app:** compact three-column history log with always-visible filters ([571d19e](https://github.com/jkrumm/ntfy-mac/commit/571d19e9bef11b4a49157a75e185a6b39b641b5e))
* **app:** detect meetings in the app and add the Meetings settings ([b3a4f20](https://github.com/jkrumm/ntfy-mac/commit/b3a4f208eae8540640fb2ab0a88895cef62b39c6))
* **app:** history window with search, filters, markdown, attachments and export ([21d0ab5](https://github.com/jkrumm/ntfy-mac/commit/21d0ab58dfa74e6dbaceddc7c21470818074c2c2))
* **app:** move the Meetings explanations into section footers ([4c8b906](https://github.com/jkrumm/ntfy-mac/commit/4c8b90685155b740155fe9018c1dc87333081fe4))
* **app:** observable app model, menu bar extra and window coordination ([a982c0d](https://github.com/jkrumm/ntfy-mac/commit/a982c0dabd4c9a68ee8f3dd9d6501f4b0d92e566))
* **app:** offer Acknowledge only on messages that need it ([feea5d0](https://github.com/jkrumm/ntfy-mac/commit/feea5d0d9fbe222317ac5a937e86104f447cc3e0))
* **app:** offscreen UI snapshots of every window and the popover ([03c72bc](https://github.com/jkrumm/ntfy-mac/commit/03c72bc7d8df909740719fc35c1f752dfb260c05))
* **app:** one group per topic in Settings ([2910e89](https://github.com/jkrumm/ntfy-mac/commit/2910e8935470f59e6242ba0f535a09a70f451ed1))
* **app:** rebuild the popover actions on MenuRow with an inline pause row ([34ca516](https://github.com/jkrumm/ntfy-mac/commit/34ca5165b6f7167ce4e3bbdaf6b275a12fea2c8b))
* **app:** roomier History and Settings windows, no truncated labels ([5bb564d](https://github.com/jkrumm/ntfy-mac/commit/5bb564dec8a567c48efb74bd513150eed7856314))
* **app:** say which priorities re-alert, and lay the section out as labelled rows ([d023533](https://github.com/jkrumm/ntfy-mac/commit/d023533c5d86e09deddcfcebe4b48c704f96905d))
* **app:** settings window, onboarding and the settings parity tests ([2fa9bcf](https://github.com/jkrumm/ntfy-mac/commit/2fa9bcfed0ba561ae46973feab69fcef300bb848))
* **app:** show meeting state and a presenting toggle in the menu popover ([86c0586](https://github.com/jkrumm/ntfy-mac/commit/86c05867d8139a35591a67eca9046702fba04d55))
* **app:** sounds and dismiss time as one table ([bcbd5ea](https://github.com/jkrumm/ntfy-mac/commit/bcbd5ea49aacd666c557c70b5d48be8f889e89e5))
* **app:** user notification adapters and app composition root ([111d390](https://github.com/jkrumm/ntfy-mac/commit/111d3905bdd2a300c9c2c1007dc38563118c794a))
* **cli:** add config meeting, present and the meeting in status ([ecc8272](https://github.com/jkrumm/ntfy-mac/commit/ecc8272235bc7c24a880617c360cef64cc174530))
* **cli:** config get/set/reset, topic and quiet-hours commands, settings catalog ([adc5605](https://github.com/jkrumm/ntfy-mac/commit/adc5605250f0295808b2ff54fcb25d48ef91aab5))
* **client:** stream events, catch-up poller, account topics, https-only tokens ([7f5e5be](https://github.com/jkrumm/ntfy-mac/commit/7f5e5bee15ca93380cf71742d4b94d027a1faf7e))
* **cli:** output layer, exit codes and the full 1.x command port ([0dcd112](https://github.com/jkrumm/ntfy-mac/commit/0dcd11219ffd94b984a4586b573255694305f432))
* **cli:** status, history, tail, wait, publish, pause, login-item and schema commands ([148ddb5](https://github.com/jkrumm/ntfy-mac/commit/148ddb5583f00224f916cdca5dba426d54861ab6))
* **cli:** verify and install updates for direct installs ([c6a4748](https://github.com/jkrumm/ntfy-mac/commit/c6a47489189795ab30daa3ff19edd179acb9360e))
* **cli:** warn about duplicate installs and refuse a curl install over Homebrew ([0f6c4c6](https://github.com/jkrumm/ntfy-mac/commit/0f6c4c6989b59d24ebc6f7a703463a2af034de5c))
* **core:** add meeting detection policy, monitor and config group ([35150c7](https://github.com/jkrumm/ntfy-mac/commit/35150c7e98fd7d11eae0fa286e665785984ea59c))
* **core:** config file compatibility, Keychain token migration, state cursor ([59277d1](https://github.com/jkrumm/ntfy-mac/commit/59277d111e26861671dbe157f3f95962f6043666))
* **core:** delivery policy, priority profiles, tag emoji map and link safety ([d8ee948](https://github.com/jkrumm/ntfy-mac/commit/d8ee94856f073fedb8e2a58a0a3344462cd4d317))
* **core:** delivery service with paced queue, re-alert, auto-dismiss and boot reconcile ([4b17da5](https://github.com/jkrumm/ntfy-mac/commit/4b17da541e020242153594ce2988b3cbee7aeb4f))
* **core:** hold notifications while a meeting is detected ([aa6f052](https://github.com/jkrumm/ntfy-mac/commit/aa6f052cc0cb8a9f1089b5432c661d2576aa2f03))
* **core:** notification response handling, safe image and http-action fetchers, permission state ([df36f32](https://github.com/jkrumm/ntfy-mac/commit/df36f3250d070b7ac5410d0de8302541839c948d))
* **core:** per-topic mute, minimum priority and emoji, and quiet hours with digest ([475997f](https://github.com/jkrumm/ntfy-mac/commit/475997ffcea4048afe340fea8437cec1905526f5))
* **core:** reconnect state machine, missed-message policy, stream supervisor ([066400e](https://github.com/jkrumm/ntfy-mac/commit/066400e8126da3dd45fa16feee4e2f24bb0093c7))
* **core:** scaffold Swift package, app target and make check gate ([86d7500](https://github.com/jkrumm/ntfy-mac/commit/86d7500b54b2b82cd82eb3c96b6841f72781ab6c))
* **history:** add an Unacknowledged view with a count badge ([26e1bb6](https://github.com/jkrumm/ntfy-mac/commit/26e1bb67fb380de802e5869228561bf289d645e4))
* **history:** topic overview, delete, attachments, export and the history model ([80c57a6](https://github.com/jkrumm/ntfy-mac/commit/80c57a6d0eadc07bf523cc87ff9d841fb4ddb03a))
* **install:** make install-macbook pull through the MacBook approval dialog ([742d480](https://github.com/jkrumm/ntfy-mac/commit/742d4809f23191e02efeeb9845de1801b1ebdb48))
* **ipc:** report the meeting state in status ([972aa2e](https://github.com/jkrumm/ntfy-mac/commit/972aa2ec11b318218dd7a0b11154d095769f0135))
* **ipc:** socket transport, app-side IPC handler and persisted pause ([44f0a76](https://github.com/jkrumm/ntfy-mac/commit/44f0a7642c4e32ca30aec8d389f0e3e2f887a4e4))
* **platform:** read meeting signals from CoreAudio and CoreMediaIO ([c56d840](https://github.com/jkrumm/ntfy-mac/commit/c56d840970242ee9397675f4d875adf6fb6b296f))
* release the Swift menu bar app as 2.0.0 ([510a9d9](https://github.com/jkrumm/ntfy-mac/commit/510a9d99e9d00a034a550ae0d58ed9b8358c8fb6))
* **release:** sign with Developer ID, notarize and publish an appcast ([91bd739](https://github.com/jkrumm/ntfy-mac/commit/91bd7399a500ddb233ba6e994180182c87f92356))
* **store:** sqlite history store with fts5, ack state, retention and read-only access ([64726e3](https://github.com/jkrumm/ntfy-mac/commit/64726e33fd1a9ac8274e125e17a8abbccad2f9b1))
* **update:** update the direct channel through Sparkle ([2ad9e85](https://github.com/jkrumm/ntfy-mac/commit/2ad9e8545e3e99a5e259e0bb85d495ae94d65250))


### BREAKING CHANGES

* ntfy-mac 2.0 is a native Swift menu bar app and replaces the 1.x bash
daemon. The Homebrew service and LaunchAgent are replaced by a login item (`brew services`
no longer runs anything), the token moves from `config.json` into the Keychain on first
launch, and notification permission must be allowed once more because the bundle id changed.
See "Upgrading from 1.x" in the README.
* ntfy-mac 2.0 is a native Swift app. The Bun daemon, the
ntfy-notify helper app and the TypeScript tooling are gone. The first
launch of 2.0 migrates a 1.x install: it moves the token to the
Keychain, keeps config.json and state.json, and removes the old
LaunchAgent, brew service and helper app. Notification permission has to
be granted once again because the helper's bundle id changes.

# [1.11.0](https://github.com/jkrumm/ntfy-mac/compare/v1.10.1...v1.11.0) (2026-04-01)


### Features

* **notifications:** add permission checking and improved troubleshooting ([576a2c5](https://github.com/jkrumm/ntfy-mac/commit/576a2c551c9bf4042f49bbca151d0130c7a7195c))

## [1.10.1](https://github.com/jkrumm/ntfy-mac/compare/v1.10.0...v1.10.1) (2026-03-25)


### Bug Fixes

* **stability:** address CodeRabbit review feedback on cleanup logic ([6b1a5c4](https://github.com/jkrumm/ntfy-mac/commit/6b1a5c4fae1d0bb2c35621c927b9c2a2d51126f5))
* **stability:** unified installation cleanup and SSE error logging ([83be0bc](https://github.com/jkrumm/ntfy-mac/commit/83be0bc50b5922e0fe313b3cea3cd681eceae969))

# [1.10.0](https://github.com/jkrumm/ntfy-mac/compare/v1.9.0...v1.10.0) (2026-03-25)


### Bug Fixes

* **notifications:** prevent duplicate app registration and dock bounce ([71a6e22](https://github.com/jkrumm/ntfy-mac/commit/71a6e227c25d72853b1c1366f37d4738fe42c822))


### Features

* **topics:** add subscribe/unsubscribe CLI commands ([454baca](https://github.com/jkrumm/ntfy-mac/commit/454bacac662a9deb73475852afa8cbb25dffa525))

# [1.9.0](https://github.com/jkrumm/ntfy-mac/compare/v1.8.0...v1.9.0) (2026-03-23)


### Features

* **notifications:** add default action buttons with daemon-side reminders ([d821836](https://github.com/jkrumm/ntfy-mac/commit/d8218361772375c7bf4edfeb02073aca52a34295))
* **notifications:** revise default sounds per priority level ([68f2e55](https://github.com/jkrumm/ntfy-mac/commit/68f2e5510ea22be7440789a853f4bbf0f86edc5f))

# [1.8.0](https://github.com/jkrumm/ntfy-mac/compare/v1.7.0...v1.8.0) (2026-03-22)


### Features

* **notifications:** add sound preview command and fix p1 visibility ([b26bf21](https://github.com/jkrumm/ntfy-mac/commit/b26bf2153a12dbab924d78e8902b76b78caf767c))

# [1.7.0](https://github.com/jkrumm/ntfy-mac/compare/v1.6.0...v1.7.0) (2026-03-22)


### Features

* **notifications:** add configurable auto-dismiss timing ([8980325](https://github.com/jkrumm/ntfy-mac/commit/898032547e5f9323d48017fc010fbb28d0321235))

# [1.6.0](https://github.com/jkrumm/ntfy-mac/compare/v1.5.0...v1.6.0) (2026-03-21)


### Bug Fixes

* **release:** also update resource URL in Homebrew formula ([63c0be9](https://github.com/jkrumm/ntfy-mac/commit/63c0be93ccf1b16a774460799887045e4b5bf113)), closes [Resource#version](https://github.com/Resource/issues/version)


### Features

* add comprehensive CLI features and diagnostics ([a68a4e3](https://github.com/jkrumm/ntfy-mac/commit/a68a4e37a5f721c0f92ae397edc90fe5383a36fe))
* **notify:** add local notification command ([f85f7e2](https://github.com/jkrumm/ntfy-mac/commit/f85f7e26b9cc8988626c2691d74f7b33aea8d79c))

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
