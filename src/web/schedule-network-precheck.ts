// Scheduled-task network-readiness pre-check (task-config `requires.network_hosts`).
// Companion to schedule-mcp-precheck.ts: that file proves a required MCP
// server's PROCESS is alive; this one proves the network stack the task
// actually needs (DNS resolution of a declared host, e.g. the mail server)
// is UP before the runner injects the prompt.
//
// Why this is a separate gate and not just requires.mcp_servers: a boot-race
// incident (2026-09-01) showed the two failure modes are independent. The
// email MCP's stdio subprocess is forked as part of the Claude session
// starting -- it exists within a second or two. But its first real network
// call (SMTP connect) can still hit CONNECT_TIMEOUT for tens of seconds
// after boot, while WiFi/DNS/Tailscale are still settling. A process-liveness
// check goes green in that window; only an actual DNS resolution attempt
// (bounded by a timeout, so a slow-but-eventually-fine resolver does not hang
// the tick) observes the real gap.
//
// FAIL-OPEN by design, same contract as the MCP precheck: a task with no
// requires.network_hosts is entirely unaffected.

import { lookup } from 'node:dns/promises'
import { logger } from '../logger.js'

export interface NetworkPrecheckResult {
  ok: boolean
  // Hosts that failed to resolve OR did not resolve within the timeout.
  // A slow resolver and a failed one are indistinguishable to the caller by
  // design -- both mean "not safely usable yet", and the retry queue will
  // try again next tick regardless of which one it was.
  missing: string[]
}

export const NETWORK_PRECHECK_TIMEOUT_MS = 3000

// Injectable so tests can control resolution speed/outcome without touching
// real DNS or waiting on real wall-clock time.
export type LookupFn = (host: string) => Promise<unknown>

const defaultLookup: LookupFn = (host) => lookup(host)

// Races a real lookup against a timer. The timer resolving first is treated
// exactly like a lookup rejection: "not ready", not an error to propagate --
// the caller only cares about ready vs. not-ready.
async function resolvesWithinTimeout(host: string, timeoutMs: number, lookupFn: LookupFn): Promise<boolean> {
  let timer: ReturnType<typeof setTimeout> | undefined
  const timedOut = new Promise<boolean>((resolve) => {
    timer = setTimeout(() => resolve(false), timeoutMs)
  })
  try {
    return await Promise.race([
      lookupFn(host).then(() => true).catch(() => false),
      timedOut,
    ])
  } finally {
    if (timer) clearTimeout(timer)
  }
}

export async function checkNetworkHosts(
  hosts: string[],
  timeoutMs: number = NETWORK_PRECHECK_TIMEOUT_MS,
  lookupFn: LookupFn = defaultLookup,
): Promise<NetworkPrecheckResult> {
  if (hosts.length === 0) return { ok: true, missing: [] }
  const results = await Promise.all(
    hosts.map(async (host) => ({ host, ok: await resolvesWithinTimeout(host, timeoutMs, lookupFn) })),
  )
  const missing = results.filter((r) => !r.ok).map((r) => r.host)
  return { ok: missing.length === 0, missing }
}

// Thin wrapper used by the runner: logs the outcome so a deferral is never a
// silent gap in the logs, mirroring checkTaskMcpRequirements's contract.
export async function checkTaskNetworkRequirements(
  hosts: string[],
  taskName: string,
  agentName: string,
): Promise<NetworkPrecheckResult> {
  const result = await checkNetworkHosts(hosts)
  if (!result.ok) {
    logger.warn(
      { task: taskName, agent: agentName, hosts, missing: result.missing, timeoutMs: NETWORK_PRECHECK_TIMEOUT_MS },
      'Required network host(s) unreachable (DNS did not resolve within timeout) -- deferring task',
    )
  }
  return result
}
