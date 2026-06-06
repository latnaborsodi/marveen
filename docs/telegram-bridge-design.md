# Telegram Bridge Liveness Detection & Recovery — Design

Status: Re-scoped 2026-06-03 (most of this design is now SUPERSEDED by live upstream code)
Date: 2026-06-03

---

## RE-SCOPE 2026-06-03 — read this first

The install was rebased onto `upstream/main` (HEAD `df3cd48`, live). The channel-stability
wave already shipped and is running:

- `#226` deafness-recovery, `#240` (no respawn when plugin alive), `#228/#229/#230` channel-monitor.
- `src/web/inbound-probe.ts` — an **active** deafness watchdog: a telethon userbot sends a real
  `__wd_ping`, the TS side scans the session transcript JSONL (`readLastIngestionTimestamp`,
  matching `<channel source=`) for ingestion since the marker. No ingestion → staged respawn.
- `src/web/telegram.ts` already calls `getMe` (token validation + bot-username cache).

**Do NOT rebuild any of the above.** The active round-trip probe is a strictly stronger
liveness signal than the passive Tier 2/Tier 3 design below, so most of this doc is superseded.

### The two open questions — RESOLVED

1. **Polling or webhook? → MOOT.** Upstream never calls external `getUpdates`/`getWebhookInfo`
   for liveness. The userbot synthetic round-trip + transcript scan sidesteps the whole
   "external getUpdates steals the plugin's updates" risk. The polling-vs-webhook distinction
   no longer gates anything.
2. **Does the marveen backend see inbound Telegram events? → NO.** The plugin is in-process in
   the claude session; there is no backend intake handler. Liveness is derived by scanning the
   session transcript (`readLastIngestionTimestamp`). Therefore there is **no place and no need**
   for a `channel_health.last_event_at` SQLite write. The `channel_health` table was never created
   in `db.ts` and should NOT be added — the transcript is the source of truth.

### Remaining UNIQUE, unimplemented piece (minimal — Lukács)

Everything passive in the Tier 3 / SQLite plan is superseded. The only residual value is a
thin **Tier 2 back-off guard**:

- A periodic `getMe` probe used **only** to suppress *futile* respawns: if the bot token is
  revoked (HTTP 401/403) or the Telegram API is down (timeout/5xx), do NOT respawn — alert (401/403)
  or back off (5xx). Layer this as a guard on the existing inbound-probe respawn decision in
  `channel-monitor.ts` / `inbound-probe.ts`. ~30 LOC, no new table, no new intake path.
- **Drop `getWebhookInfo`**: the plugin is in-process (not webhook mode), so it has near-zero value.
- If, after review, the existing respawn already behaves acceptably without the guard, this task
  is **closeable** with no code.

### Assessment: guard IS needed (2026-06-03)

Reviewed `inbound-probe.ts` in full. The existing `checkInboundProbeDeafness()` function calls
`hardRestartMarveenChannels()` directly once `shouldTriggerDeafnessRespawn()` returns true. No
token validity or API reachability check precedes the respawn decision.

**Failure mode confirmed — Telegram API down (5xx/timeout):**

1. t=0: prober sends `__wd_ping` successfully → `PROBE_LAST_SENT_FILE` updated.
2. t=3min: prober tries to send again, Telegram API is down → telethon exception → file NOT updated.
3. t=6min: TS check tick — `markerTs = t0`, `nowMs - markerTs = 6min ≥ probeTimeoutMs (2×3min)`.
   `lastIngestionTs < markerTs` (no ingestion since t0, because the ping never arrived) → `needsRespawn = true`.
4. `hardRestartMarveenChannels()` fires → **futile respawn**, Telegram API is the problem not the session**.

**Failure mode confirmed — token revoked (401/403):**
Same path: prober can't send → file not updated → timeout → respawn → loop. Restart cannot fix a revoked token.

**Conclusion: the ~30 LOC guard prevents both failure modes. Task is NOT closeable without code.**

### Implementation spec (for Donat review — no code until approved)

**File:** `src/web/inbound-probe.ts`

**Change:** make `checkInboundProbeDeafness` async; add `checkBotTokenHealth()` call before
the respawn path.

```typescript
// Bot token health check — call only when deafness is already confirmed,
// to avoid adding latency to every monitor tick.
async function checkBotTokenHealth(): Promise<{ ok: boolean; statusCode?: number }> {
  const env = readEnvFile(['TELEGRAM_BOT_TOKEN'])
  const token = env['TELEGRAM_BOT_TOKEN']
  if (!token) return { ok: true }  // no token configured — not our problem to gate
  try {
    const res = await fetch(`https://api.telegram.org/bot${token}/getMe`, { signal: AbortSignal.timeout(8000) })
    return { ok: res.ok, statusCode: res.status }
  } catch {
    return { ok: false }  // network error / timeout
  }
}

// In checkInboundProbeDeafness(), after `if (!needsRespawn) return`:
const health = await checkBotTokenHealth()
if (!health.ok) {
  if (health.statusCode === 401 || health.statusCode === 403) {
    logger.error({ statusCode: health.statusCode }, 'Bot token invalid/revoked -- skipping respawn, alerting')
    // notifyChannel imported via dynamic import same as hardRestartMarveenChannels
    sendAlert('🚨 Telegram bot token ÉRVÉNYTELEN (401/403). Respawn nem segít -- új tokent kell beállítani.')
  } else {
    logger.warn({ statusCode: health.statusCode }, 'Telegram API unreachable -- deferring respawn to next tick')
  }
  return
}
// Telegram API up + token valid + deafness confirmed → proceed with existing respawn
```

**Token source:** `readEnvFile(['TELEGRAM_BOT_TOKEN'])` — same pattern already used in
`readAllowedChatId()` and `readProbeIntervalMs()` in this file.

**Branch:** `feat/inbound-probe-tier2-guard` — NOT main.

**Scope:** ~35 LOC diff, no new table, no new intake path, no behaviour change for the healthy path.

The rest of this document is the original passive design, retained for context only.

---

## Context

Claude Code v2.1.150+ runs the Telegram plugin in-process: `claude --channels plugin:telegram`. There is no separate bun-bridge process to watch. The transient bun grandchild worker appears and disappears at will — its absence is not an outage signal.

**The two failure modes we need to distinguish:**

| Mode | Description | Correct response |
|------|-------------|------------------|
| Session down | claude process not running with the channels flag | Staged recovery (soft → resume → hard restart) |
| Silent plugin failure | claude runs with correct cmdline, but plugin receives no Telegram events | API probe, then staged recovery |

**What's currently broken:**

1. `telegram-bridge-watchdog.sh` restarts `jezus-channels` every 7 minutes regardless of actual health. This is preemptive, timer-based, and wrong.
2. The channel monitor's `hasChannelPluginAlive()` for Telegram only checks the cmdline flag — it cannot detect silent in-process failures (claude alive, plugin wedged).

**Goal:** No false "dead" signals. No unnecessary restarts. Restart only when the plugin is demonstrably broken after exhausting cheaper fixes.

---

## Liveness Signals — Three Tiers

### Tier 1 — Process / Cmdline (already implemented)

`channel-monitor.ts` checks: does the claude session's cmdline contain both `--channels` and `plugin:telegram`?

- If NO: the session is not correctly configured or not running. Escalate to recovery.
- If YES: the session is running with the correct flags. This rules out "session not started" but does NOT rule out silent plugin failure.

Cost: zero — one `ps` scan already running in the monitor loop.

### Tier 2 — Telegram Bot API Health Check (new)

If Tier 1 is green, periodically call `GET https://api.telegram.org/bot<TOKEN>/getMe` from the marveen backend (not from the claude session).

- HTTP 200 + `ok: true`: Telegram's side is reachable with this token. The bot credentials are valid.
- HTTP 4xx (401/403): token invalid or revoked. Alert immediately — no restart will fix this.
- Timeout / 5xx: Telegram API outage. Do NOT escalate to recovery — back off and retry.

This check is outbound HTTP from the dashboard process. It does not inject anything into the claude session and has no side effects.

Cost: one HTTP GET per check interval. Should run no more than once per 5 minutes.

### Tier 3 — Last Inbound Event Timestamp (new)

When the Telegram plugin successfully delivers an event to the claude session, record a timestamp in SQLite. This is the strongest liveness signal: it proves the full path works (Telegram → plugin → session delivery).

**Schema addition to `claudeclaw.db`:**

```sql
CREATE TABLE IF NOT EXISTS channel_health (
  agent_id TEXT NOT NULL,
  provider TEXT NOT NULL DEFAULT 'telegram',
  last_event_at INTEGER,       -- unix epoch of last successfully delivered inbound event
  last_probe_at INTEGER,       -- unix epoch of last Tier 2 API probe
  last_probe_ok INTEGER,       -- 1 = probe succeeded, 0 = failed
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (agent_id, provider)
);
```

**Who writes `last_event_at`:** The marveen web server already receives Telegram events through the channel plugin pipeline (or the API bridge). The event handler writes `last_event_at = unixepoch()` on every inbound message before routing it to the claude session.

**If `last_event_at` is NULL or too old:** Tier 2 API probe is triggered. If Tier 2 also fails: escalate to recovery.

---

## The Hard Case: Silent Plugin Failure

Symptom: Tier 1 green (claude cmdline correct), but no Telegram events arriving for an extended period.

This has two innocent explanations:
- Nobody is sending messages (quiet time, off-hours).
- The Tier 2 API probe passes (bot credentials valid).

And one failure explanation:
- The in-process plugin opened its WebSocket connection to Telegram, but the connection silently dropped (TCP keepalive timeout, Telegram backend restart, etc.).

**How to distinguish silence from failure:**

We cannot without a probe that generates a synthetic round-trip. Three options:

**Option A — Synthetic Telegram message (NOT recommended)**
Send the bot a message to itself via the API (allowed by Telegram). If it arrives at the plugin, the path works. Downside: adds noise to the chat history; failure to arrive is ambiguous (could be Telegram delay).

**Option B — `getUpdates` poll (recommended for Phase 1)**
Call `GET /getUpdates?offset=-1&timeout=0` from the marveen backend. This does NOT affect the plugin's own long-poll connection if the plugin uses the webhooks mode (which the claude-code telegram plugin does). If `getUpdates` returns normally (even with empty `result`), the Telegram API connection is valid for this token.

Limitation: `getUpdates` in polling mode conflicts with webhooks. Need to confirm the plugin uses webhooks, not polling. If it uses polling (long-poll), calling `getUpdates` from outside will steal updates from the plugin — do NOT do this. Use Tier 2 (`getMe`) only in that case.

**Option C — Webhook status check (recommended if webhooks confirmed)**
Call `GET /getWebhookInfo`. Returns the webhook URL and `last_error_date`/`last_error_message`. If `last_error_date` is recent (within the threshold), the webhook is failing. This is a strong, non-invasive signal.

**Recommended Phase 1 probe:** `getMe` (Tier 2) + `getWebhookInfo` if webhook mode is confirmed. These are read-only, side-effect-free.

---

## Activity-Window Aware Thresholds

A 30-minute event silence at 3:00 AM is normal. At 14:00 on a workday it is suspicious.

| Time window | Last-event threshold to trigger Tier 2 probe |
|-------------|----------------------------------------------|
| 08:00 – 22:00 | 45 minutes without inbound event |
| 22:00 – 08:00 | 4 hours without inbound event |

The probe itself runs during any window if the threshold is exceeded. The recovery escalation only happens after:
1. Tier 2 probe fails (API unreachable or `getWebhookInfo` shows error), AND
2. Tier 1 is green (claude session running).

If Tier 2 passes but events are still absent: **do not restart**. The system is healthy; users are not writing.

---

## Recovery Strategy

The existing staged recovery in `channel-monitor.ts` is correct in structure. Keep it as-is, with one addition: only enter the recovery pipeline after both Tier 1 and Tier 2 have failed.

```
[Tier 1: cmdline check]
    │
    ├─ FAIL → enter recovery immediately (session not running)
    │
    └─ PASS → [Tier 2: getMe + getWebhookInfo]
                  │
                  ├─ FAIL → enter recovery
                  │
                  └─ PASS + event silence within window → wait (not an outage)

Recovery stages (unchanged):
  Stage 1: soft /mcp reconnect (up to 3 attempts, silent)
  Stage 2: memory-save prompt to session (60s window)
  Stage 3: session resume (tmux respawn-pane --continue)
  Stage 4: hard restart (systemctl --user restart jezus-channels)
  Stage 5: alert + give up (human must intervene)
```

**Confirmation window (already in place):** `MARVEEN_DOWN_CONFIRM_MS = 120_000` — two consecutive failures must be observed before entering Stage 1. This prevents single-tick transients from triggering recovery.

---

## What to Disable: The Watchdog

`~/marveen/scripts/telegram-bridge-watchdog.sh` restarts `jezus-channels` after 7 minutes of uptime, unconditionally. This:
- Kills healthy sessions mid-conversation.
- Prevents Stage 3 (session resume with `--continue`) from working, because the session was just hard-reset.
- Adds churn that masks whether the plugin is actually failing.

**Action:** Identify and disable the cron job or systemd timer that calls this script. The script itself can remain as a file (for reference), but should not be scheduled.

Check what invokes it:
```bash
crontab -l | grep watchdog
systemctl --user list-timers | grep watchdog
grep -r watchdog ~/.claude/ ~/marveen/ --include="*.json" --include="*.yaml"
```

After disabling: the `channel-monitor.ts` staged recovery handles all restart decisions.

---

## Implementation Plan

These are changes to the marveen backend (`~/marveen/src/`), not to `tourguide`. Donat reviews the design first; no code until approved.

### Phase 1 — Disable watchdog + add Tier 2 probe

> SUPERSEDED 2026-06-03 — see RE-SCOPE block at top. Items 1/2/3 are done or dropped upstream;
> only a trimmed item 4 (getMe back-off guard, no getWebhookInfo) survives.

1. ~~Disable the preemptive watchdog cron/timer.~~ Handled by the live inbound-probe stack.
2. ~~Add `channel_health` table migration to `db.ts`.~~ DROPPED — no backend intake path; transcript is source of truth.
3. ~~Add `last_event_at` write in the Telegram event intake path.~~ DROPPED — superseded by `readLastIngestionTimestamp` (transcript scan).
4. Add a **getMe-only** back-off guard (NOT `getWebhookInfo`) layered on the existing inbound-probe
   respawn decision: skip respawn on 401/403 (alert) or 5xx/timeout (back off). ~30 LOC.
5. ~~Update `shouldEscalateMarveenDown()`~~ → instead, gate the existing inbound-probe respawn with item 4.

### Phase 2 — Dashboard visibility

6. Expose `channel_health` via `/api/channel-health` endpoint.
7. Dashboard widget: "Telegram last event: X minutes ago | API probe: OK/FAIL".

### What we are deliberately leaving out

| Item | Reason |
|------|--------|
| Synthetic round-trip message | Noisy, ambiguous, Telegram API rate-limit risk |
| Per-message delivery confirmation | Would require modifying the claude plugin internals |
| Automatic webhook re-registration | Not needed if `getWebhookInfo` is healthy; over-engineered for Phase 1 |
| Watchdog script deletion | Keep it as a reference artifact; just de-schedule it |

---

## Risks & Open Questions

1. **Does the telegram plugin use polling or webhooks?** This determines whether `getUpdates` can be called from outside (polling = off-limits). Need to confirm by checking the plugin source or `getWebhookInfo` response on a live session. If webhooks: `getWebhookInfo` is the preferred Tier 2 probe.

2. **Where is the bot token stored for the marveen backend?** The channel-monitor.ts uses `readChannelToken(providerType, envPath)`. The Tier 2 probe needs the same token. Need to confirm the path (likely `store/.env` or a `store/telegram/state/.env`).

3. **Tier 2 probe frequency**: once per 5 minutes during business hours is safe. Telegram's Bot API rate limit is 30 req/sec global, so one `getMe` per 5 minutes poses zero risk.

4. **What triggers `last_event_at` write?** The marveen web server receives Telegram events — need to identify the exact handler function in the codebase. Likely in `src/web/` or the channel plugin intake path.

5. **Backward compatibility of `channel_health` table:** nullable columns, no NOT NULL on timestamps — graceful if the writer fails to update. The Tier 2 probe falls back to polling-based check if `last_event_at` is NULL.
