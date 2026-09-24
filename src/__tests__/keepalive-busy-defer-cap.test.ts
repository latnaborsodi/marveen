import { describe, it, expect, vi, beforeEach, afterAll } from 'vitest'
import { rmSync, writeFileSync, utimesSync } from 'node:fs'
import { join } from 'node:path'

// tebez #126 -- FAILURE TEST for the keepalive busy-defer hard cap.
//
// THE BUG (measured, twice, on jezus-channels): when store/.channel-keepalive
// goes stale the watchdog respawns the main pane -- UNLESS the pane reads
// busy/typing, in which case it defers. That defer had no upper bound, and a
// wedged Claude TUI renders exactly like a working one, so the watchdog kept
// deferring on every sweep:
//   * 2026-09-17 17:07 -> 09-18 06:51: 13h43m, 2612 'deferring respawn' lines.
//   * 2026-09-22 12:36 -> 09-23 09:51: 21h, 1297 lines -- the rad-var morning
//     digest, the kanban audit, the dream-engine, the tebez daily triage and
//     the invoice-forward run all silently missed. A MANUAL restore ended it,
//     not the watchdog.
// The stuck-input arm of the same watchdog already had a 15-minute cap
// (7b156ec); this suite pins the twin cap on the keepalive arm.
//
// WHAT A GREEN RESULT CLAIMS: with the keepalive stale and the pane reporting
// busy without interruption, `tmux respawn-pane` is NOT executed at minute 14,
// and IS executed at minute 16. The assertion is on the real side effect (the
// tmux command line), not on the decider's return value -- this is the same
// path that hard-restarts the live session in production.
//
// POSITIVE CONTROL FIRST (see the kapu-es-merce-tervezes rules): before any
// "it defers" assertion, the suite proves the fixture can respawn at all -- an
// idle pane with a stale keepalive respawns on the first sweep. Without that,
// a broken fixture (nothing ever respawns) would make every defer assertion
// green on a dead test.

const h = vi.hoisted(() => {
  // Hoisted with the mock factories: they reference SANDBOX, and vi.mock runs
  // before any top-level const in this file is initialised.
  const os = require('node:os') as typeof import('node:os')
  const fs = require('node:fs') as typeof import('node:fs')
  const path = require('node:path') as typeof import('node:path')
  const SANDBOX = fs.mkdtempSync(path.join(os.tmpdir(), 'keepalive-cap-'))
  fs.mkdirSync(path.join(SANDBOX, 'store'), { recursive: true })
  const SEP = '─'.repeat(80)
  const BUSY = [
    '✢ Combobulating… (52s · ↓ 2.6k tokens · thinking some more)',
    '',
    SEP,
    '❯ ',
    SEP,
    '  ⏵⏵ bypass permissions on (shift+tab to cycle) · esc to interrupt',
  ].join('\n')
  const IDLE = [
    '',
    SEP,
    '❯ ',
    SEP,
    '  ⏵⏵ bypass permissions on (shift+tab to cycle)',
  ].join('\n')
  return {
    SANDBOX,
    BUSY,
    IDLE,
    pane: BUSY,
    execCalls: [] as string[][],
  }
})

const SANDBOX = h.SANDBOX

// tmux/ps/pgrep all go through execFileSync. Recording it gives us the exact
// production side effect to assert on: `tmux respawn-pane -k -t <session> ...`.
vi.mock('node:child_process', async (orig) => {
  const actual = await orig<typeof import('node:child_process')>()
  return {
    ...actual,
    execFileSync: vi.fn((file: string, args?: string[]) => {
      if (Array.isArray(args)) {
        h.execCalls.push([file, ...args])
        if (args.includes('capture-pane')) return h.pane
      }
      // list-panes / ps / pgrep -> empty: getClaudePidForSession reads null, so
      // the live-poller trust shortcut never fires and we reach the busy guard.
      return ''
    }),
    spawn: vi.fn(() => ({ unref: () => {} })),
  }
})

// No `claude`/`tmux` binary is required to run this suite.
vi.mock('../platform.js', async (orig) => {
  const actual = await orig<typeof import('../platform.js')>()
  return { ...actual, makeLazyBinResolver: (name: string) => () => `/usr/bin/${name}` }
})

vi.mock('../config.js', async (orig) => {
  const actual = await orig<typeof import('../config.js')>()
  return { ...actual, PROJECT_ROOT: h.SANDBOX, STORE_DIR: `${h.SANDBOX}/store`, RESPAWN_ENABLED: true }
})

vi.mock('../logger.js', () => ({
  logger: { info: vi.fn(), warn: vi.fn(), debug: vi.fn(), error: vi.fn() },
}))

vi.mock('../notify.js', () => ({
  notifyChannel: vi.fn(async () => {}),
  notifyTelegram: vi.fn(async () => {}),
}))

// Keep the respawn helper on its real code path, but stub the bits that would
// touch the operator's actual ~/.claude during a unit run.
vi.mock('../web/agent-process.js', async (orig) => {
  const actual = await orig<typeof import('../web/agent-process.js')>()
  return {
    ...actual,
    ensureSharedClaudeOnboarded: vi.fn(() => {}),
    ensureMainAgentIsolatedConfigDir: vi.fn(() => null),
    hasFleetOauthToken: vi.fn(() => false),
    scheduleIdentitySetup: vi.fn(async () => {}),
  }
})

vi.mock('../web/channel-plugin-unlock.js', async (orig) => {
  const actual = await orig<typeof import('../web/channel-plugin-unlock.js')>()
  return { ...actual, schedulePluginUnlockAfterRespawn: vi.fn(() => {}) }
})

// No transcript in the sandbox -> no inbound timestamp -> the keepalive file we
// stamp below is the only staleness input.
vi.mock('../web/inbound-probe.js', async (orig) => {
  const actual = await orig<typeof import('../web/inbound-probe.js')>()
  return { ...actual, readLastIngestionTimestamp: vi.fn(() => null) }
})

import {
  checkMainKeepaliveStaleness,
  shouldDeferKeepaliveRespawnWithCap,
  KEEPALIVE_BUSY_DEFER_CAP_MS,
  STUCK_RESTART_HARD_CAP_MS,
} from '../web/channel-monitor.js'

const KEEPALIVE_FILE = join(SANDBOX, 'store', '.channel-keepalive')
const MINUTE = 60_000

let clock = 1_800_000_000_000
vi.spyOn(Date, 'now').mockImplementation(() => clock)

/** Age the keepalive file to `ageMs` relative to the current fake clock. */
function stampKeepalive(ageMs: number): void {
  writeFileSync(KEEPALIVE_FILE, String(Math.floor((clock - ageMs) / 1000)))
  const when = new Date(clock - ageMs)
  utimesSync(KEEPALIVE_FILE, when, when)
}

function respawns(): string[][] {
  return h.execCalls.filter(c => c.includes('respawn-pane'))
}

/**
 * One watchdog sweep at `atMs` on the fake clock, with the keepalive stale by
 * `keepaliveAgeMs` (default: well past the 18-minute threshold).
 */
function sweep(atMs: number, paneContent: string, keepaliveAgeMs = 60 * MINUTE): void {
  clock = atMs
  h.pane = paneContent
  stampKeepalive(keepaliveAgeMs)
  checkMainKeepaliveStaleness()
}

// The defer streak is module state, so each test starts from a clean one: a
// sweep with a FRESH keepalive is the in-band reset (healthy channel -> no
// streak), the same thing that ends a streak in production.
beforeEach(() => {
  h.pane = h.BUSY
  stampKeepalive(1 * MINUTE)
  checkMainKeepaliveStaleness()
  h.execCalls.length = 0
})

afterAll(() => {
  rmSync(SANDBOX, { recursive: true, force: true })
})

describe('keepalive busy-defer hard cap (tebez #126)', () => {
  // POSITIVE CONTROL. If this fails, every assertion below is meaningless --
  // the fixture cannot respawn at all, so "no respawn" proves nothing.
  it('POSITIVE CONTROL: a stale keepalive on an IDLE pane respawns immediately', () => {
    sweep(clock + 10 * MINUTE, h.IDLE)
    expect(respawns().length).toBe(1)
  })

  it('still defers at 14 minutes of uninterrupted busy deferral', () => {
    const t0 = clock + 60 * MINUTE // clear of the post-respawn grace
    sweep(t0, h.BUSY)
    expect(respawns().length).toBe(0)
    sweep(t0 + 7 * MINUTE, h.BUSY)
    sweep(t0 + 14 * MINUTE, h.BUSY)
    expect(respawns().length).toBe(0)
  })

  // THE FAILURE TEST. Without the cap this is red: the pre-fix code deferred on
  // every sweep for as long as the pane read busy (measured: 13h43m and 21h).
  it('RESPAWNS at minute 16 even though the pane still reads busy', () => {
    const t0 = clock + 60 * MINUTE
    sweep(t0, h.BUSY)
    sweep(t0 + 8 * MINUTE, h.BUSY)
    expect(respawns().length).toBe(0)

    sweep(t0 + 16 * MINUTE, h.BUSY)
    expect(respawns().length).toBe(1)
    // The real side effect, on the real session, with -k (kill the running pane).
    expect(respawns()[0]).toContain('respawn-pane')
    expect(respawns()[0]).toContain('-k')
  })

  it('never fires on a COUNT of sweeps -- only on elapsed time', () => {
    const t0 = clock + 60 * MINUTE
    // 30 sweeps packed into 5 minutes: far more log lines than the 13h43m
    // incident produced per quarter hour, but nowhere near the cap in time.
    for (let i = 0; i < 30; i++) sweep(t0 + i * 10_000, h.BUSY)
    expect(respawns().length).toBe(0)
    // ...and one more sweep past the cap does fire.
    sweep(t0 + 16 * MINUTE, h.BUSY)
    expect(respawns().length).toBe(1)
  })

  it('needs a CONTINUOUS stretch -- a healthy sweep in between restarts the clock', () => {
    const t0 = clock + 60 * MINUTE
    sweep(t0, h.BUSY)
    // The keepalive goes fresh in between: the channel recovered on its own,
    // so the busy-defer streak must start over rather than carry its age.
    sweep(t0 + 10 * MINUTE, h.BUSY, 1 * MINUTE)
    expect(respawns().length).toBe(0)
    // 16 minutes after the FIRST busy sweep, but the streak restarts here.
    sweep(t0 + 16 * MINUTE, h.BUSY)
    expect(respawns().length).toBe(0)
    // 15 minutes into the NEW streak (not the old one) the cap fires.
    sweep(t0 + 31 * MINUTE, h.BUSY)
    expect(respawns().length).toBe(1)
  })
})

describe('shouldDeferKeepaliveRespawnWithCap', () => {
  const capMs = KEEPALIVE_BUSY_DEFER_CAP_MS

  it('defers a busy pane below the cap, and stops deferring at/after it', () => {
    expect(shouldDeferKeepaliveRespawnWithCap({ paneState: 'busy', deferredForMs: 0, capMs })).toBe(true)
    expect(shouldDeferKeepaliveRespawnWithCap({ paneState: 'busy', deferredForMs: capMs - 1, capMs })).toBe(true)
    expect(shouldDeferKeepaliveRespawnWithCap({ paneState: 'busy', deferredForMs: capMs, capMs })).toBe(false)
    expect(shouldDeferKeepaliveRespawnWithCap({ paneState: 'typing', deferredForMs: capMs + 1, capMs })).toBe(false)
  })

  it('never defers a pane that is not busy, whatever the age', () => {
    for (const st of ['idle', 'unknown', 'error', null] as const) {
      expect(shouldDeferKeepaliveRespawnWithCap({ paneState: st, deferredForMs: 0, capMs })).toBe(false)
    }
  })

  it('uses the same 15 minutes as the stuck-input arm of the same watchdog', () => {
    expect(KEEPALIVE_BUSY_DEFER_CAP_MS).toBe(15 * 60 * 1000)
    expect(KEEPALIVE_BUSY_DEFER_CAP_MS).toBe(STUCK_RESTART_HARD_CAP_MS)
  })
})
