// APPROVALVAK821: the approval gate was a closed loop -- three independent
// legs, each silently non-delivering:
//   (1) creation never sent anything to the owner (telegram_message_id was
//       only writable via PATCH, which nothing called),
//   (2) notifyMainAgent delivered the notification back to the REQUESTER
//       when the requester was the main agent itself,
//   (3) timeout_at was always NULL (no category carries timeout_minutes and
//       the request's timeout_seconds was never read), so the sweeper's
//       'timeout' status was structurally unreachable.
// These tests pin the fix for all three legs: the pure pieces behaviorally,
// the wiring as string contracts (house idiom of approvals-prompt-contract).
import { describe, it, expect, beforeAll, afterAll } from 'vitest'
import { readFileSync, writeFileSync, mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import {
  applyTimeoutPolicy,
  computeTimeoutAt,
  readCategoryTimeoutMinutes,
  buildOwnerApprovalText,
  DEFAULT_TIMEOUT_MINUTES,
  MAX_TIMEOUT_SECONDS,
} from '../web/routes/approvals.js'
import type { Approval } from '../db.js'

const __dirname = dirname(fileURLToPath(import.meta.url))
const ROUTE = readFileSync(join(__dirname, '../../src/web/routes/approvals.ts'), 'utf-8')
const TELEGRAM = readFileSync(join(__dirname, '../../src/web/telegram.ts'), 'utf-8')

const NOW_MS = 1_787_300_000_000

function approval(over: Partial<Approval> = {}): Approval {
  return {
    id: 'test-id-1234',
    agent_id: 'samu',
    category: 'skill_patch',
    action_description: 'Skill frissítése a mérési eredmény alapján',
    action_payload: null,
    status: 'pending',
    timeout_at: Math.floor(NOW_MS / 1000) + 3600,
    telegram_message_id: null,
    requested_at: Math.floor(NOW_MS / 1000),
    resolved_at: null,
    resolved_by: null,
    ...over,
  }
}

describe('computeTimeoutAt (leg 3: the timeout state must be reachable)', () => {
  const now = Math.floor(NOW_MS / 1000)

  it('the request timeout_seconds wins', () => {
    expect(computeTimeoutAt('nonexistent-category', 3600, NOW_MS)).toBe(now + 3600)
  })

  it('caps a timeout past a week (it would equal the old "never")', () => {
    expect(computeTimeoutAt('x', 10 * 24 * 3600, NOW_MS)).toBe(now + MAX_TIMEOUT_SECONDS)
  })

  it('ignores junk timeout_seconds and falls through', () => {
    for (const junk of ['3600', -5, 0, NaN, Infinity, null, undefined, {}]) {
      expect(computeTimeoutAt('nonexistent-category', junk, NOW_MS)).toBe(now + DEFAULT_TIMEOUT_MINUTES * 60)
    }
  })

  it('NEVER returns null: with no param and no category value the default applies', () => {
    expect(computeTimeoutAt('nonexistent-category', undefined, NOW_MS)).toBe(now + DEFAULT_TIMEOUT_MINUTES * 60)
  })
})

// APPROVALFLOOR916: the category deadline was a fallback the caller could
// silently undercut. Every scaffolded agent sent `"timeout_seconds":3600`, so
// raising a category's deadline in autonomy-config.json changed nothing -- the
// hardcoded hour won. These pin the floor semantics.
describe('applyTimeoutPolicy (the category value is a FLOOR, not a fallback)', () => {
  const HOUR = 3600
  const TWELVE_HOURS_MIN = 720

  it('a caller asking for LESS than the category floor gets the floor', () => {
    expect(applyTimeoutPolicy(HOUR, TWELVE_HOURS_MIN)).toBe(TWELVE_HOURS_MIN * 60)
  })

  it('a caller asking for MORE than the floor keeps the longer value', () => {
    expect(applyTimeoutPolicy(3 * 24 * HOUR, TWELVE_HOURS_MIN)).toBe(3 * 24 * HOUR)
  })

  it('no floor configured: the caller value stands, as before', () => {
    expect(applyTimeoutPolicy(HOUR, null)).toBe(HOUR)
  })

  it('no floor and no caller value: the 24h default stands', () => {
    expect(applyTimeoutPolicy(undefined, null)).toBe(DEFAULT_TIMEOUT_MINUTES * 60)
  })

  it('a floor with no caller value applies the floor', () => {
    expect(applyTimeoutPolicy(undefined, TWELVE_HOURS_MIN)).toBe(TWELVE_HOURS_MIN * 60)
  })

  it('junk from the caller cannot undercut the floor either', () => {
    for (const junk of ['3600', -5, 0, NaN, Infinity, null, undefined, {}]) {
      expect(applyTimeoutPolicy(junk, TWELVE_HOURS_MIN)).toBe(TWELVE_HOURS_MIN * 60)
    }
  })

  it('a zero or negative floor is treated as "no floor", not as an instant timeout', () => {
    expect(applyTimeoutPolicy(HOUR, 0)).toBe(HOUR)
    expect(applyTimeoutPolicy(HOUR, -60)).toBe(HOUR)
  })

  it('the one-week cap still wins over a caller value AND over an absurd floor', () => {
    expect(applyTimeoutPolicy(10 * 24 * HOUR, TWELVE_HOURS_MIN)).toBe(MAX_TIMEOUT_SECONDS)
    expect(applyTimeoutPolicy(undefined, 30 * 24 * 60)).toBe(MAX_TIMEOUT_SECONDS)
  })

  it('NEVER returns a non-positive span: the timeout state stays reachable', () => {
    for (const floor of [null, 0, -1, TWELVE_HOURS_MIN]) {
      for (const req of [undefined, 0, -5, HOUR]) {
        expect(applyTimeoutPolicy(req, floor)).toBeGreaterThan(0)
      }
    }
  })
})

// APPROVALFLOOR916 -- BUKAS-TESZT. Donat kikotese: uj kapuhoz kotelezo egy
// probat irni, ami SZANDEKOSAN meg tud bukni. Ez az: egy agens ugy kuld
// `timeout_seconds: 3600`-at, ahogy a regi sablon tanitotta, es a proba csak
// akkor zold, ha a keletkezo hatarido 24 ora mulva van, nem egy ora mulva.
// A config-olvasast is atfogja, nem csak a tiszta fuggvenyt, kulonben az also
// korlat bekerulhetne a politikaba ugy, hogy a valodi hivasi utvonal nem hasznalja.
describe('BUKAS-TESZT: a 3600-at kuldo regi agens is 24 orat kap', () => {
  const now = Math.floor(NOW_MS / 1000)
  let dir: string
  let configPath: string

  beforeAll(() => {
    dir = mkdtempSync(join(tmpdir(), 'approval-floor-'))
    configPath = join(dir, 'autonomy-config.json')
    writeFileSync(configPath, JSON.stringify({
      categories: [
        { key: 'email_send', level: 2, timeout_minutes: 1440 },
        { key: 'kanban_archive_done', level: 3 },
      ],
    }), 'utf-8')
  })

  afterAll(() => rmSync(dir, { recursive: true, force: true }))

  it('a fixture config timeout_minutes-e kiolvasodik', () => {
    expect(readCategoryTimeoutMinutes('email_send', configPath)).toBe(1440)
    expect(readCategoryTimeoutMinutes('kanban_archive_done', configPath)).toBeNull()
    expect(readCategoryTimeoutMinutes('nincs-ilyen', configPath)).toBeNull()
  })

  it('MAGA A BUKAS-TESZT: timeout_seconds 3600 -> a hatarido 24 ora, nem egy', () => {
    const at = computeTimeoutAt('email_send', 3600, NOW_MS, configPath)
    expect(at - now).toBe(24 * 3600)
    expect(at - now).not.toBe(3600)
  })

  it('a hosszabb keres tovabbra is atmegy, az also korlat nem plafon', () => {
    expect(computeTimeoutAt('email_send', 3 * 24 * 3600, NOW_MS, configPath) - now).toBe(3 * 24 * 3600)
  })

  it('also korlat nelkuli kategorianal a regi viselkedes marad', () => {
    expect(computeTimeoutAt('kanban_archive_done', 3600, NOW_MS, configPath) - now).toBe(3600)
  })
})

// A masik fele Donat aggalyanak: az also korlat csak akkor er valamit, ha
// EGYETLEN utvonal hoz letre jovahagyast. Ha valaki kesobb ir egy masodik
// createApproval hivast, ez a teszt bukik, es nem kivulrol kell eszrevenni.
describe('egyetlen hivasi utvonal hozhat letre jovahagyast', () => {
  it('a createApproval-t csak a POST kezelo hivja, es az computeTimeoutAt-tel szamol', () => {
    const calls = ROUTE.match(/createApproval\(/g) ?? []
    expect(calls.length).toBe(1)
    expect(ROUTE).toContain('const timeout_at = computeTimeoutAt(category, timeout_seconds)')
  })
})

describe('buildOwnerApprovalText (leg 1: what the owner reads)', () => {
  it('carries the id, requester, category and description', () => {
    const text = buildOwnerApprovalText(approval())
    expect(text).toContain('samu')
    expect(text).toContain('skill_patch')
    expect(text).toContain('Skill frissítése a mérési eredmény alapján')
    expect(text).toContain('test-id-1234')
    expect(text).toContain('Jóváhagyások')
    expect(text).not.toContain('undefined')
  })

  it('renders the expiry in local (Budapest) time, or "nincs" without one', () => {
    expect(buildOwnerApprovalText(approval())).toContain('Lejárat: 2026.')
    expect(buildOwnerApprovalText(approval({ timeout_at: null }))).toContain('Lejárat: nincs')
  })
})

describe('wiring contracts on the route source', () => {
  it('the POST handler notifies the OWNER, not only the main agent', () => {
    const post = ROUTE.slice(ROUTE.indexOf("path === '/api/approvals' && method === 'POST'"))
    const owner = post.indexOf('notifyOwner(approval)')
    const main = post.indexOf('notifyMainAgent(approval)')
    expect(owner).toBeGreaterThan(0)
    expect(main).toBeGreaterThan(owner)
  })

  it('a successful owner send stamps telegram_message_id onto the row', () => {
    expect(ROUTE).toContain('setApprovalTelegramMessageId(approval.id, messageId)')
  })

  it('leg 2: the main-agent notify short-circuits when the requester IS the main agent', () => {
    const fn = ROUTE.slice(ROUTE.indexOf('function notifyMainAgent('))
    const guard = fn.indexOf('approval.agent_id === MAIN_AGENT_ID')
    const send = fn.indexOf('createAgentMessage')
    expect(guard).toBeGreaterThan(0)
    expect(send).toBeGreaterThan(guard)
  })

  it('the POST handler reads timeout_seconds from the body', () => {
    expect(ROUTE).toContain('computeTimeoutAt(category, timeout_seconds)')
  })

  it('a failed owner send is loud, not silent', () => {
    expect(ROUTE).toContain('approval owner notification FAILED')
  })

  it('sendTelegramMessage exposes the message_id for the stamp', () => {
    expect(TELEGRAM).toContain('Promise<number | null>')
    expect(TELEGRAM).toContain('message_id')
  })
})

describe('degraded-delivery fallback (review finding on #1026)', () => {
  it('every owner-send failure path falls back to an in-band message', () => {
    const fn = ROUTE.slice(ROUTE.indexOf('function notifyOwner('))
    for (const reason of ["'no-token'", "'no-owner-chat'", "'send-failed'"]) {
      expect(fn).toContain(`fallbackInBand(approval, ${reason})`)
    }
  })

  it('the fallback is main-requester-only and carries the OWNER_UNREACHED marker', () => {
    const fn = ROUTE.slice(ROUTE.indexOf('function fallbackInBand('), ROUTE.indexOf('function notifyOwner('))
    const guard = fn.indexOf('approval.agent_id !== MAIN_AGENT_ID')
    const send = fn.indexOf('createAgentMessage')
    expect(guard).toBeGreaterThan(0)
    expect(send).toBeGreaterThan(guard)
    expect(fn).toContain('[OWNER_UNREACHED')
  })
})
