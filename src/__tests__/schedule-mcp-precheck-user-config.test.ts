import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'

// resolveMcpProcessPatterns must also read the USER-LEVEL ~/.claude.json
// (top-level mcpServers), not just PROJECT_ROOT/.mcp.json and the agent's own
// .mcp.json. Found during the 2026-09-01 boot-race review: an MCP server
// added via `claude mcp add` at user scope (this install's `email` server)
// lives ONLY there. Without this, requires.mcp_servers: ['email'] resolves to
// an unknown name and the precheck fails open -- a requirement that looks
// like a safeguard but enforces nothing.

let SANDBOX = ''

vi.mock('node:os', async (orig) => {
  const actual = await orig<typeof import('node:os')>()
  return { ...actual, homedir: () => join(SANDBOX, 'home') }
})

const { resolveMcpProcessPatterns } = await import('../web/schedule-mcp-precheck.js')

beforeEach(() => {
  SANDBOX = mkdtempSync(join(tmpdir(), 'mcp-user-cfg-'))
  mkdirSync(join(SANDBOX, 'home'), { recursive: true })
})
afterEach(() => {
  rmSync(SANDBOX, { recursive: true, force: true })
})

describe('resolveMcpProcessPatterns: user-level ~/.claude.json', () => {
  it('picks up an MCP server declared only in ~/.claude.json top-level mcpServers', () => {
    writeFileSync(
      join(SANDBOX, 'home', '.claude.json'),
      JSON.stringify({
        mcpServers: {
          email: { command: 'npx', args: ['-y', 'mcp-mail-server'] },
        },
        // A realistic ~/.claude.json also carries a `projects` map; the
        // resolver must ignore it, not choke on unrelated shape.
        projects: { '/some/path': { mcpServers: {} } },
      }),
    )
    const patterns = resolveMcpProcessPatterns(null)
    // Neither arg contains '/', so deriveProcessPattern falls back to
    // command + first-arg (this install's real email server config has no
    // path-bearing arg, unlike the gmail-readonly example elsewhere).
    expect(patterns.email).toBe('npx -y')
  })

  it('missing ~/.claude.json is fail-open (no throw, just absent from the map)', () => {
    const patterns = resolveMcpProcessPatterns(null)
    expect(patterns).toEqual({})
  })

  it('unparsable ~/.claude.json is fail-open, not a crash', () => {
    writeFileSync(join(SANDBOX, 'home', '.claude.json'), '{ not valid json')
    expect(() => resolveMcpProcessPatterns(null)).not.toThrow()
    expect(resolveMcpProcessPatterns(null)).toEqual({})
  })
})
