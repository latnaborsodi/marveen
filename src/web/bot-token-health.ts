/**
 * Fork-only (latnaborsodi): Telegram bot-token health probe.
 *
 * Tier 2 back-off guard: before a deafness respawn, verify the Telegram API is
 * reachable and the bot token is valid. A futile respawn (Telegram down or token
 * revoked) wastes a hard-restart and masks the real cause.
 *
 * Kept in its own module so upstream merges of inbound-probe.ts don't drop it.
 *
 * Returns:
 *   { ok: true }                    — token valid, Telegram reachable
 *   { ok: false, statusCode: 401 }  — token invalid or revoked
 *   { ok: false, statusCode: 403 }  — token forbidden
 *   { ok: false }                   — Telegram API down (5xx) or network error
 */
export async function checkBotTokenHealth(token: string): Promise<{ ok: boolean; statusCode?: number }> {
  if (!token) return { ok: true }  // no token configured — not our concern here
  try {
    const res = await fetch(`https://api.telegram.org/bot${token}/getMe`, {
      signal: AbortSignal.timeout(8000),
    })
    return { ok: res.ok, statusCode: res.status }
  } catch {
    return { ok: false }  // network error or timeout
  }
}
