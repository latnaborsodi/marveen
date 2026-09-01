import { describe, it, expect, vi, beforeEach } from 'vitest'

// The "requires.mcp_servers names an unresolvable server" case used to log at
// debug, which a normal deployment's log level filters out entirely -- the
// same failure shape as an empty rule file that LOOKS like it enforces
// something but silently doesn't (2026-09-01 review, named explicitly by the
// operator: "a deklarált requires, ami csendben semmire nem oldódik fel,
// rosszabb, mint ha nem lenne"). Fail-open is still correct (a typo'd or
// differently-shaped requirement must never block an unrelated task); only
// the VISIBILITY of the gap changes here, to warn.

const mockWarn = vi.fn()
const mockDebug = vi.fn()

vi.mock('../logger.js', () => ({
  logger: { info: vi.fn(), warn: mockWarn, debug: mockDebug, error: vi.fn() },
}))

vi.mock('node:child_process', () => ({
  execFileSync: vi.fn(() => [
    '  PID  PPID COMMAND',
    '    1     0 /sbin/launchd',
    '  200     1 claude',
  ].join('\n')),
}))

vi.mock('../channel-coordinator/liveness.js', () => ({
  getClaudePidForSession: vi.fn(() => 200),
}))

const { checkTaskMcpRequirements } = await import('../web/schedule-mcp-precheck.js')

beforeEach(() => {
  mockWarn.mockClear()
  mockDebug.mockClear()
})

describe('checkTaskMcpRequirements: unknown server name visibility', () => {
  it('logs at WARN (not just debug) when a required server has no derivable process pattern', () => {
    const result = checkTaskMcpRequirements(['definitely-not-a-configured-server-xyz'], 'testagent', 'test-session', null)
    expect(result.ok).toBe(true) // still fail-open, never blocks
    expect(result.unknown).toEqual(['definitely-not-a-configured-server-xyz'])
    expect(mockWarn).toHaveBeenCalledTimes(1)
    expect(mockWarn.mock.calls[0][0]).toMatchObject({ unknown: ['definitely-not-a-configured-server-xyz'] })
  })
})
