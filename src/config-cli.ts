import { readdirSync } from "fs"
import { join } from "path"
import { homedir } from "os"
import { loadStoredConfig, updateStoredConfig } from "./config"
import { PRIORITY_CONFIG } from "./notify"

// ─── Sound discovery ─────────────────────────────────────────────────────────

const SYSTEM_SOUNDS_DIR = "/System/Library/Sounds"
const USER_SOUNDS_DIR = join(homedir(), "Library", "Sounds")

export function discoverSounds(): string[] {
  const sounds: string[] = []
  for (const dir of [SYSTEM_SOUNDS_DIR, USER_SOUNDS_DIR]) {
    try {
      for (const file of readdirSync(dir)) {
        if (file.endsWith(".aiff") || file.endsWith(".wav") || file.endsWith(".caf")) {
          sounds.push(file.replace(/\.(aiff|wav|caf)$/, ""))
        }
      }
    } catch {
      // Directory doesn't exist or unreadable
    }
  }
  return [...new Set(sounds)].sort()
}

// ─── Config show ─────────────────────────────────────────────────────────────

function priorityLabel(p: number): string {
  const labels: Record<number, string> = {
    5: "urgent",
    4: "high",
    3: "default",
    2: "low",
    1: "min",
  }
  return labels[p] ?? String(p)
}

async function showSoundsConfig(): Promise<void> {
  const stored = await loadStoredConfig()
  const userSounds = (stored.sounds ?? {}) as Record<string, string | null>

  console.log("Notification sounds\n")
  console.log("  Priority      Sound         Source")
  console.log("  ────────────  ────────────  ──────")

  for (let p = 5; p >= 1; p--) {
    const userSound = userSounds[String(p)]
    const defaultSound = PRIORITY_CONFIG[p]?.sound ?? null
    const effective = userSound !== undefined ? userSound : defaultSound
    const source = userSound !== undefined ? "custom" : "default"
    const soundDisplay = effective ?? "(silent)"
    const label = `${p} (${priorityLabel(p)})`
    console.log(`  ${label.padEnd(14)}${soundDisplay.padEnd(14)}${source}`)
  }

  console.log("")
  console.log("Change with: ntfy-mac config sounds set <priority> <sound>")
  console.log("Reset all:   ntfy-mac config sounds reset")
  console.log("List sounds: ntfy-mac config sounds list")
  console.log('Test:        ntfy-mac notify -m "test" -p <priority>')
}

// ─── Config sounds subcommands ───────────────────────────────────────────────

async function handleSoundsCommand(args: string[]): Promise<void> {
  const sub = args[0]

  if (!sub || sub === "show") {
    await showSoundsConfig()
    return
  }

  if (sub === "list") {
    const sounds = discoverSounds()
    console.log("Available notification sounds:\n")
    for (const s of sounds) console.log(`  ${s}`)
    console.log(`\n  (silent)  — no sound`)
    console.log(`\nFound ${sounds.length} sounds.`)
    console.log("Custom sounds can be added to ~/Library/Sounds/ (AIFF/WAV/CAF, max 30s).")
    return
  }

  if (sub === "set") {
    const priority = parseInt(args[1], 10)
    const sound = args[2]

    if (!args[1] || !sound) {
      console.error("Usage: ntfy-mac config sounds set <priority 1-5> <sound|silent>")
      console.error("Example: ntfy-mac config sounds set 5 Glass")
      console.error("Example: ntfy-mac config sounds set 2 silent")
      process.exit(1)
    }
    if (isNaN(priority) || priority < 1 || priority > 5) {
      console.error("Priority must be 1-5.")
      process.exit(1)
    }

    const soundValue = sound === "silent" ? null : sound

    // Validate sound exists
    if (soundValue !== null) {
      const available = discoverSounds()
      if (!available.includes(soundValue)) {
        console.error(`Unknown sound: ${soundValue}`)
        console.error(`Run 'ntfy-mac config sounds list' to see available sounds.`)
        process.exit(1)
      }
    }

    const stored = await loadStoredConfig()
    const existing = (stored.sounds ?? {}) as Record<string, string | null>
    existing[String(priority)] = soundValue
    await updateStoredConfig({ sounds: existing })

    const display = soundValue ?? "(silent)"
    console.log(`Priority ${priority} (${priorityLabel(priority)}) → ${display}`)
    console.log('Test it: ntfy-mac notify -m "test" -p ' + priority)
    return
  }

  if (sub === "reset") {
    await updateStoredConfig({ sounds: undefined })
    console.log("Sound configuration reset to defaults.")
    await showSoundsConfig()
    return
  }

  console.error(`Unknown sounds subcommand: ${sub}`)
  console.error("Available: show, list, set, reset")
  process.exit(1)
}

// ─── Config dismiss show ─────────────────────────────────────────────────────

async function showDismissConfig(): Promise<void> {
  const stored = await loadStoredConfig()
  const userDismiss = (stored.dismiss ?? {}) as Record<string, number>

  console.log("Auto-dismiss timing\n")
  console.log("  Priority      Dismiss       Source")
  console.log("  ────────────  ────────────  ──────")

  for (let p = 5; p >= 1; p--) {
    const userValue = userDismiss[String(p)]
    const defaultValue = PRIORITY_CONFIG[p]?.dismissAfter ?? 0
    const effective = userValue !== undefined ? userValue : defaultValue
    const source = userValue !== undefined ? "custom" : "default"
    const display = effective === 0 ? "never" : `${effective}s`
    const label = `${p} (${priorityLabel(p)})`
    console.log(`  ${label.padEnd(14)}${display.padEnd(14)}${source}`)
  }

  console.log("")
  console.log("Change with: ntfy-mac config dismiss set <priority> <seconds|never>")
  console.log("Reset all:   ntfy-mac config dismiss reset")
  console.log('Test:        ntfy-mac notify -m "test" -p <priority>')
}

// ─── Config dismiss subcommands ──────────────────────────────────────────────

async function handleDismissCommand(args: string[]): Promise<void> {
  const sub = args[0]

  if (!sub || sub === "show") {
    await showDismissConfig()
    return
  }

  if (sub === "set") {
    const priority = Number(args[1])
    const value = args[2]

    if (!args[1] || !value) {
      console.error("Usage: ntfy-mac config dismiss set <priority 1-5> <seconds|never>")
      console.error("Example: ntfy-mac config dismiss set 3 10")
      console.error("Example: ntfy-mac config dismiss set 5 never")
      process.exit(1)
    }
    if (!Number.isInteger(priority) || priority < 1 || priority > 5) {
      console.error("Priority must be 1-5.")
      process.exit(1)
    }

    const seconds = value === "never" ? 0 : Number(value)
    if (value !== "never" && (!Number.isFinite(seconds) || seconds < 0)) {
      console.error("Value must be a positive number (seconds) or 'never'.")
      process.exit(1)
    }

    const stored = await loadStoredConfig()
    const existing = (stored.dismiss ?? {}) as Record<string, number>
    existing[String(priority)] = seconds
    await updateStoredConfig({ dismiss: existing })

    const display = seconds === 0 ? "never" : `${seconds}s`
    console.log(`Priority ${priority} (${priorityLabel(priority)}) → ${display}`)
    console.log('Test it: ntfy-mac notify -m "test" -p ' + priority)
    return
  }

  if (sub === "reset") {
    await updateStoredConfig({ dismiss: undefined })
    console.log("Dismiss configuration reset to defaults.")
    await showDismissConfig()
    return
  }

  console.error(`Unknown dismiss subcommand: ${sub}`)
  console.error("Available: show, set, reset")
  process.exit(1)
}

// ─── Config entry point ──────────────────────────────────────────────────────

async function showConfigOverview(): Promise<void> {
  const stored = await loadStoredConfig()
  const userSounds = (stored.sounds ?? {}) as Record<string, string | null>
  const userDismiss = (stored.dismiss ?? {}) as Record<string, number>

  console.log("Notification configuration\n")
  console.log("  Priority      Sound         Dismiss")
  console.log("  ────────────  ────────────  ────────────")

  for (let p = 5; p >= 1; p--) {
    const config = PRIORITY_CONFIG[p]
    const label = `${p} (${priorityLabel(p)})`

    const userSound = userSounds[String(p)]
    const effectiveSound = userSound !== undefined ? userSound : (config?.sound ?? null)
    const soundDisplay = effectiveSound ?? "(silent)"
    const soundStr = userSound !== undefined ? `${soundDisplay}*` : soundDisplay

    const userDismissVal = userDismiss[String(p)]
    const effectiveDismiss =
      userDismissVal !== undefined ? userDismissVal : (config?.dismissAfter ?? 0)
    const dismissDisplay = effectiveDismiss === 0 ? "never" : `${effectiveDismiss}s`
    const dismissStr = userDismissVal !== undefined ? `${dismissDisplay}*` : dismissDisplay

    console.log(`  ${label.padEnd(14)}${soundStr.padEnd(14)}${dismissStr}`)
  }

  console.log("")
  console.log("  * = custom override")
  console.log("")
  console.log("Commands:")
  console.log("  ntfy-mac config sounds              Manage notification sounds")
  console.log("  ntfy-mac config dismiss              Manage auto-dismiss timing")
  console.log('  ntfy-mac notify -m "test" -p <1-5>   Test a priority level')
}

export async function handleConfigCommand(args: string[]): Promise<void> {
  const sub = args[0]

  if (!sub) {
    await showConfigOverview()
    return
  }

  if (sub === "sounds") {
    await handleSoundsCommand(args.slice(1))
    return
  }

  if (sub === "dismiss") {
    await handleDismissCommand(args.slice(1))
    return
  }

  console.error(`Unknown config subcommand: ${sub}`)
  console.error("Available: sounds, dismiss")
  process.exit(1)
}
