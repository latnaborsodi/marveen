// Scheduled-task MCP availability pre-check (Roitman 22.5: skill manifest
// `requires`). A task can declare `requires.mcp_servers` in task-config.json;
// before the runner injects the prompt it verifies that each named MCP server
// has a LIVE process under the target session's claude process tree. A dead
// server then defers the task (pending-retry queue + reasoned Telegram alert)
// instead of the prompt failing at runtime inside the session -- the
// 2026-07-08 failure class, where the morning briefing ran against a silently
// dead gmail MCP and nobody was told.
//
// FAIL-OPEN by design: the pre-check only blocks when it can positively prove
// a required server is absent. Remote sessions, an unresolvable claude PID,
// or a server name with no derivable process pattern all pass with a debug
// log -- a broken pre-check must never become a new way to silently starve
// scheduled tasks.

import { existsSync, readFileSync } from 'node:fs'
import { join } from 'node:path'
import { homedir } from 'node:os'
import { execFileSync } from 'node:child_process'
import { logger } from '../logger.js'
import { PROJECT_ROOT } from '../config.js'
import { agentDir } from './agent-config.js'
import { getClaudePidForSession } from '../channel-coordinator/liveness.js'

interface McpServerDef {
  command?: string
  args?: string[]
}

// -- Pattern derivation ------------------------------------------------------

// A stdio MCP server's most distinctive ps signature is its script path (the
// first arg containing '/'); node/python interpreter paths are shared across
// servers so `command` alone would cross-match. Fall back to command+first-arg
// for servers launched as a bare binary (e.g. `garmin-mcp`).
export function deriveProcessPattern(def: McpServerDef): string | null {
  const pathArg = (def.args ?? []).find((a) => a.includes('/'))
  if (pathArg) return pathArg
  if (def.command) {
    const first = (def.args ?? [])[0]
    return first ? `${def.command} ${first}` : def.command
  }
  return null
}

// Merge the USER-LEVEL ~/.claude.json, the project-root .mcp.json, and the
// agent's own .mcp.json (later entries win on name collision), returning
// name -> ps pattern. Missing/unparsable files yield {}.
//
// The user-level file was missing here until 2026-09-01 (found while
// investigating the boot-race incident): an MCP server added via `claude mcp
// add` at the user scope (e.g. this install's `email` server) lives ONLY in
// ~/.claude.json's top-level `mcpServers`, never in a project or agent
// .mcp.json. Without this, requires.mcp_servers: ['email'] would resolve
// 'email' to an UNKNOWN name and the precheck fails open (see
// decideMcpPrecheck below) -- a declared requirement that silently protects
// nothing, which is worse than no requirement at all because it looks like a
// safeguard.
export function resolveMcpProcessPatterns(agentName: string | null): Record<string, string> {
  const out: Record<string, string> = {}
  const files = [join(homedir(), '.claude.json'), join(PROJECT_ROOT, '.mcp.json')]
  if (agentName) {
    try {
      files.push(join(agentDir(agentName), '.mcp.json'))
    } catch {
      /* unknown agent -> root config only */
    }
  }
  for (const file of files) {
    try {
      if (!existsSync(file)) continue
      const cfg = JSON.parse(readFileSync(file, 'utf-8')) as { mcpServers?: Record<string, McpServerDef> }
      for (const [name, def] of Object.entries(cfg.mcpServers ?? {})) {
        const pattern = deriveProcessPattern(def)
        if (pattern) out[name] = pattern
      }
    } catch {
      /* unparsable config -> skip file (fail-open) */
    }
  }
  return out
}

// -- Live process collection --------------------------------------------------

// Command lines of every process under `rootPid` (the session's claude
// process), from a single `ps` snapshot. Same parent-map walk as
// decideHasPluginAlive in channel-coordinator/liveness.ts.
export function collectSubtreeCmdlines(psOutput: string, rootPid: number): string[] {
  const childrenOf = new Map<number, number[]>()
  const cmdOf = new Map<number, string>()
  for (const line of psOutput.split('\n').slice(1)) {
    const m = line.match(/^\s*(\d+)\s+(\d+)\s+(.*)$/)
    if (!m) continue
    const pid = parseInt(m[1], 10)
    const ppid = parseInt(m[2], 10)
    cmdOf.set(pid, m[3])
    const arr = childrenOf.get(ppid) ?? []
    arr.push(pid)
    childrenOf.set(ppid, arr)
  }
  const cmdlines: string[] = []
  const stack = [rootPid]
  const seen = new Set<number>()
  while (stack.length) {
    const pid = stack.pop()!
    if (seen.has(pid)) continue
    seen.add(pid)
    const cmd = cmdOf.get(pid)
    if (cmd) cmdlines.push(cmd)
    for (const child of childrenOf.get(pid) ?? []) stack.push(child)
  }
  return cmdlines
}

// -- Pure decision -------------------------------------------------------------

export interface McpPrecheckResult {
  ok: boolean
  /** Required servers with a known pattern and NO live process (blocks). */
  missing: string[]
  /** Required servers whose pattern could not be derived (fail-open, logged). */
  unknown: string[]
}

export function decideMcpPrecheck(
  required: string[],
  patterns: Record<string, string>,
  cmdlines: string[],
): McpPrecheckResult {
  const missing: string[] = []
  const unknown: string[] = []
  for (const name of required) {
    const pattern = patterns[name]
    if (!pattern) {
      unknown.push(name)
      continue
    }
    if (!cmdlines.some((cmd) => cmd.includes(pattern))) missing.push(name)
  }
  return { ok: missing.length === 0, missing, unknown }
}

// -- Orchestration --------------------------------------------------------------

/**
 * Verify a task's required MCP servers are alive under the target session.
 * Returns ok:true (with empty lists) whenever absence cannot be proven:
 * remote host, unresolvable claude PID, ps failure, or no requirements.
 */
export function checkTaskMcpRequirements(
  required: string[] | undefined,
  agentName: string,
  session: string,
  host: string | null,
): McpPrecheckResult {
  if (!required || required.length === 0) return { ok: true, missing: [], unknown: [] }
  if (host) {
    logger.debug({ agent: agentName, session }, 'MCP pre-check skipped: remote session')
    return { ok: true, missing: [], unknown: [] }
  }
  const claudePid = getClaudePidForSession(session)
  if (claudePid == null) {
    logger.debug({ agent: agentName, session }, 'MCP pre-check skipped: claude pid unresolved')
    return { ok: true, missing: [], unknown: [] }
  }
  let psOutput: string
  try {
    psOutput = execFileSync('/bin/ps', ['-axo', 'pid,ppid,command'], { timeout: 3000, encoding: 'utf-8' })
  } catch {
    logger.debug({ agent: agentName, session }, 'MCP pre-check skipped: ps failed')
    return { ok: true, missing: [], unknown: [] }
  }
  const result = decideMcpPrecheck(
    required,
    resolveMcpProcessPatterns(agentName),
    collectSubtreeCmdlines(psOutput, claudePid),
  )
  if (result.unknown.length) {
    logger.debug(
      { agent: agentName, session, unknown: result.unknown },
      'MCP pre-check: no process pattern derivable for some required servers (fail-open)',
    )
  }
  return result
}
