# ntfy-mac Marketing Strategy

Working document for building awareness. Prioritized by impact vs effort.

---

## Unique Selling Points

1. **Only native macOS client for ntfy** — the official docs say to use a PWA. The one Electron alternative (ntfy-desktop by Aetherinox) exists but isn't native. ntfy-mac is the only option that integrates with Notification Center, Focus mode, Keychain, and launchd.

2. **Reliable notification delivery** — SSE streaming + offline recovery + deduplication. PWA notifications silently fail when the browser restarts, tabs get suspended, or the Mac sleeps. ntfy-mac catches up on everything it missed.

3. **Zero maintenance** — launchd daemon starts on login, auto-reconnects, auto-discovers topics, auto-updates. Configure once, never touch again.

4. **Full ntfy feature parity** — priorities, emoji tags, images, action buttons, click URLs. Not a stripped-down wrapper.

---

## Brand Voice

Technical, honest, understated. A developer sharing a tool they built because the existing options didn't work. Not a product launch — a solution to a real problem.

**Do:** State facts. Show architecture decisions. Explain trade-offs.
**Don't:** Use superlatives. Trash ntfy itself. Sound like a landing page.

Position ntfy-mac as the missing piece that makes ntfy complete on macOS — extending the ecosystem, not competing with it.

### Tone by Platform

| Platform                         | Voice                  | Example angle                                                             |
| -------------------------------- | ---------------------- | ------------------------------------------------------------------------- |
| Reddit (r/selfhosted, r/macapps) | Peer sharing a tool    | "I built this because PWA notifications kept failing on me"               |
| Hacker News                      | Technical depth        | "Show HN: Native macOS daemon for ntfy — SSE, offline recovery, dedup"    |
| Dev.to / Medium                  | Tutorial / comparison  | "Why I replaced ntfy's PWA with a native macOS daemon"                    |
| Product Hunt                     | Concise, benefit-first | "Reliable ntfy notifications on macOS — native daemon, not a browser tab" |
| GitHub PRs                       | Contributor tone       | "Adding ntfy-mac to the integrations list"                                |
| Lemmy (discuss.ntfy.sh)          | Community member       | "Built a native macOS client — feedback welcome"                          |

---

## Competitive Landscape

| Tool                      | Type        | Strength        | Gap                                                          |
| ------------------------- | ----------- | --------------- | ------------------------------------------------------------ |
| ntfy PWA                  | Official    | Zero install    | Unreliable on macOS, no Focus mode, no offline recovery      |
| ntfy-desktop (Aetherinox) | Electron    | Cross-platform  | Not native, no launchd, no dedup, no missed message recovery |
| Notify (Flathub)          | GTK4        | Linux native    | Linux only                                                   |
| ntfyd                     | Zig daemon  | Lightweight     | No macOS notification integration                            |
| Pushover                  | Proprietary | Polished        | Paid, no self-hosting                                        |
| Gotify                    | Self-hosted | Simple admin UI | No macOS client, iOS workaround fragile                      |

ntfy-mac's position: the native macOS client that ntfy should have shipped. Complements the server, doesn't replace it.

---

## Marketing Actions

### Tier 1 — High Impact, Low Effort (this week)

- [ ] **PR to ntfy integrations.md** — Add ntfy-mac to [github.com/binwiederhier/ntfy/integrations.md](https://github.com/binwiederhier/ntfy). This is the single highest-leverage action. Every ntfy user looking for clients sees this list. Follow the existing format, keep the description to one line.

- [ ] **Post to r/selfhosted** — The primary community for ntfy users. Title should be first-person, problem-focused: "I built a native macOS daemon for ntfy because PWA notifications kept failing". Engage in comments authentically. Don't link-dump and leave.

- [ ] **Post to r/macapps** — Focus on the native macOS angle. These users care about macOS integration quality, Homebrew install, launchd, Notification Center. Less about ntfy internals, more about the Mac experience.

- [ ] **Post to r/commandline** — Focus on CLI UX: `doctor` command, local notify for scripts/cron, `sounds` preview. This audience appreciates well-designed CLI tools.

- [ ] **Post on discuss.ntfy.sh (Lemmy)** — The ntfy community migrated here from Reddit (r/ntfy is permanently closed). Introduce the project, ask for feedback. Community members may help surface issues or spread the word.

### Tier 2 — High Impact, Medium Effort (this month)

- [ ] **Show HN post** — Post Tuesday or Wednesday around 9am ET. Title: "Show HN: ntfy-mac – Native macOS notification daemon for ntfy". Include technical details in the comment — SSE architecture, offline recovery strategy, dedup approach. HN rewards solid engineering over feature lists. Be ready to answer questions for the first 2-3 hours.

- [ ] **awesome-selfhosted PR** — Add to [github.com/awesome-selfhosted/awesome-selfhosted](https://github.com/awesome-selfhosted/awesome-selfhosted) under Communication > Notification Providers or a relevant subcategory.

- [ ] **awesome-macos PR** — Add to [github.com/jaywcjlove/awesome-mac](https://github.com/jaywcjlove/awesome-mac) under a relevant utilities section.

- [ ] **awesome-cli-apps PR** — Add to [github.com/agarrharr/awesome-cli-apps](https://github.com/agarrharr/awesome-cli-apps).

- [ ] **Dev.to comparison article** — Title: "ntfy on macOS: PWA vs Electron vs Native". Structure: problem → what I tried → what I built → architecture → results. Include architecture diagram. Tag: #opensource #macos #notifications #selfhosted.

### Tier 3 — Medium Impact, Medium Effort (next 2 months)

- [ ] **Product Hunt launch** — Prepare: 3-4 screenshots/GIFs, tagline, description. Launch Tuesday-Thursday. Multiple launches are valid (Raycast launched 11 times). Coordinate with selfhosted community for launch-day support.

- [ ] **Dev.to tutorial article** — "Setting up reliable homelab notifications with ntfy + ntfy-mac". Walk through full setup: ntfy server → topic subscriptions → ntfy-mac install → monitoring integration (Uptime Kuma/Grafana). Practical, copy-paste-friendly.

- [ ] **Medium cross-post** — Cross-post Dev.to articles to Medium. Target "Better Programming" or "Towards Dev" publications for reach. Minimal extra effort.

- [ ] **YouTube homelab outreach** — Reach out to homelab YouTubers (Techno Tim, NetworkChuck, Jeff Geerling's community, DB Tech). Short pitch: "Built a native macOS ntfy client, here's a link if you want to try it." Don't ask for a video — let them decide. Some will try it and mention it organically.

### Tier 4 — Long-tail / Ongoing

- [ ] **Monitor mentions** — Set up Google Alerts for "ntfy macos", "ntfy desktop notifications". Check Reddit search periodically for threads asking about ntfy on Mac. Reply helpfully when relevant — don't spam.

- [ ] **Engage in ntfy GitHub discussions** — Answer questions where ntfy-mac is relevant. Be helpful first, mention the tool second.

- [ ] **SEO blog post** — Write "ntfy macos notifications" optimized post on a personal blog or project site. Targets long-tail Google searches from people looking for exactly this.

- [ ] **Hashnode cross-post** — Low effort if already writing on Dev.to. Good for SEO diversity.

---

## Content Drafts

### Reddit r/selfhosted

```text
Title: I built a native macOS daemon for ntfy because PWA notifications kept failing

I run ntfy for homelab alerts (Uptime Kuma, Grafana, cron jobs) and the
recommended desktop approach — keeping a browser tab open for PWA
notifications — was unreliable. Notifications stopped when the browser
restarted, arrived late when tabs were suspended, and there was no way to
recover messages missed while the Mac was asleep.

So I built ntfy-mac. It's a native macOS daemon that:

- Connects via SSE — real-time, no polling
- Runs as a launchd service — survives reboots, no browser needed
- Recovers missed messages after reconnect (sleep, network change, etc.)
- Deduplicates — reconnect doesn't mean seeing everything twice
- Maps priorities to macOS interruption levels — urgent breaks through
  Focus/DND
- Supports all ntfy features: tags, images, action buttons, click URLs

Install:
  brew install jkrumm/tap/ntfy-mac
  ntfy-mac setup

It auto-discovers your subscribed topics and just works. Been running it
for months — zero missed notifications through sleep/wake cycles, network
switches, and server restarts.

GitHub: https://github.com/jkrumm/ntfy-mac

Happy to answer questions about the setup or how it works under the hood.
```

### Show HN

```text
Title: Show HN: ntfy-mac – Native macOS notification daemon for ntfy

ntfy-mac connects to your ntfy server via SSE and delivers messages
through macOS Notification Center as a background daemon.

I built it because the recommended desktop approach (PWA in a browser tab)
was unreliable on macOS — notifications stopped on browser restart, missed
messages during sleep, no Focus mode integration.

How it works:
- Bun/TypeScript compiled to single ARM64 binary
- Swift helper for UNUserNotificationCenter delivery
- SSE streaming with exponential backoff (5s → 5min)
- Network detection via scutil --nwi (suppresses false reconnect alerts)
- Missed message recovery: polls server for gap on reconnect
- Dedup via persisted message IDs (48h TTL, 1000 entry cap)
- Priority → macOS interruption level mapping (urgent breaks through DND)
- Auto-discovers subscribed topics every 30min
- Launchd daemon with PID lock for single-instance

Install: brew install jkrumm/tap/ntfy-mac

https://github.com/jkrumm/ntfy-mac
```

### Dev.to Article Outline

```text
Title: Why I replaced ntfy's PWA with a native macOS daemon

1. The problem
   - ntfy is great for push notifications from homelab/infra
   - Desktop = "keep a browser tab open" (PWA)
   - This doesn't work: browser restarts, tab suspension, no offline
     recovery, no Focus mode

2. What exists
   - PWA (official) — requires browser, silently fails
   - ntfy-desktop (Electron) — better, but not native, no dedup/recovery
   - osascript hacks — fragile, no persistence

3. What I built
   - Architecture: SSE → Bun daemon → Swift notification helper
   - Why SSE over WebSocket (ntfy uses SSE natively, simpler reconnect)
   - Offline recovery: on reconnect, poll since=<last_seen_id>
   - Dedup: persist message IDs, 48h TTL, 1000 cap
   - Priority mapping to macOS interruption levels

4. Results
   - Zero missed notifications over months of use
   - Handles sleep/wake, network changes, server restarts
   - One command install via Homebrew

5. Try it
   - brew install jkrumm/tap/ntfy-mac && ntfy-mac setup
```

---

## Automation

| Task                                  | How                                                     | Cost               |
| ------------------------------------- | ------------------------------------------------------- | ------------------ |
| Monitor "ntfy desktop/macos" mentions | Google Alerts (free)                                    | 0                  |
| Reddit thread monitoring              | Reddit search RSS or manual weekly check                | 0                  |
| Cross-posting articles                | Write on Dev.to, manually cross-post to Medium/Hashnode | 30 min per article |
| GitHub stars tracking                 | GitHub API, optional Bun script                         | 0                  |
| Article drafting                      | Draft with AI, manually edit for authentic voice        | Time only          |

For articles: AI can draft structure and technical content, but always rewrite intros/conclusions manually. Reddit and HN communities detect and penalize AI-generated content. The authentic angle (developer solving own problem) is the strongest hook — lean into it.

---

## Key Metrics to Watch

- GitHub stars (vanity, but signals traction)
- Homebrew install count (`brew info jkrumm/tap/ntfy-mac` won't show this, but GitHub release download counts will)
- ntfy integrations.md PR acceptance
- Reddit post engagement (upvotes, comments, saves)
- HN post score and comment quality
- Dev.to article views and reactions
