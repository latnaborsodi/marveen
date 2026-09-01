import { describe, it, expect, vi, afterEach } from 'vitest'
import { checkNetworkHosts } from '../web/schedule-network-precheck.js'

// Network-readiness pre-check (task-config `requires.network_hosts`, 2026-09-01
// boot-race incident review): a task fired within seconds of the host booting
// can have its required MCP's process already running while DNS/WiFi/Tailscale
// are still settling. checkNetworkHosts proves the network path itself, not
// just process liveness -- and must not hang the scheduler tick on a resolver
// that is merely SLOW rather than outright failing.

describe('checkNetworkHosts', () => {
  afterEach(() => {
    vi.useRealTimers()
  })

  it('ok=true, missing=[] when every host resolves', async () => {
    const lookupFn = vi.fn(async () => ({ address: '1.2.3.4' }))
    const result = await checkNetworkHosts(['vps.example.hu', 'mail.example.hu'], 1000, lookupFn)
    expect(result).toEqual({ ok: true, missing: [] })
    expect(lookupFn).toHaveBeenCalledWith('vps.example.hu')
    expect(lookupFn).toHaveBeenCalledWith('mail.example.hu')
  })

  it('names only the hosts that fail to resolve, not the ones that succeed', async () => {
    const lookupFn = vi.fn(async (host: string) => {
      if (host === 'dead.example.hu') throw new Error('ENOTFOUND')
      return { address: '1.2.3.4' }
    })
    const result = await checkNetworkHosts(['ok.example.hu', 'dead.example.hu'], 1000, lookupFn)
    expect(result.ok).toBe(false)
    expect(result.missing).toEqual(['dead.example.hu'])
  })

  it('empty host list is trivially ok (task without requires.network_hosts is unaffected)', async () => {
    const lookupFn = vi.fn()
    const result = await checkNetworkHosts([], 1000, lookupFn)
    expect(result).toEqual({ ok: true, missing: [] })
    expect(lookupFn).not.toHaveBeenCalled()
  })

  it('a resolver that is merely SLOW (never fails, just takes too long) counts as missing -- must not hang the tick', async () => {
    vi.useFakeTimers()
    // Resolves eventually, but only after 10s -- far past the 1s timeout used
    // below. A real boot-race resolver in this state would otherwise wedge
    // the scheduler tick until it finally answers.
    const lookupFn = vi.fn(() => new Promise((resolve) => {
      setTimeout(() => resolve({ address: '1.2.3.4' }), 10_000)
    }))
    const promise = checkNetworkHosts(['slow.example.hu'], 1000, lookupFn)
    await vi.advanceTimersByTimeAsync(1000)
    const result = await promise
    expect(result).toEqual({ ok: false, missing: ['slow.example.hu'] })
  })

  it('resolves just under the timeout still counts as ready', async () => {
    vi.useFakeTimers()
    const lookupFn = vi.fn(() => new Promise((resolve) => {
      setTimeout(() => resolve({ address: '1.2.3.4' }), 500)
    }))
    const promise = checkNetworkHosts(['fast-enough.example.hu'], 1000, lookupFn)
    await vi.advanceTimersByTimeAsync(500)
    const result = await promise
    expect(result).toEqual({ ok: true, missing: [] })
  })

  it('checks hosts in parallel, not serially -- one slow host does not delay judging a fast sibling', async () => {
    vi.useFakeTimers()
    const lookupFn = vi.fn((host: string) => new Promise((resolve, reject) => {
      const delay = host === 'slow.example.hu' ? 900 : 50
      setTimeout(() => (host === 'slow.example.hu' ? reject(new Error('timeout')) : resolve({})), delay)
    }))
    const promise = checkNetworkHosts(['fast.example.hu', 'slow.example.hu'], 1000, lookupFn)
    await vi.advanceTimersByTimeAsync(900)
    const result = await promise
    expect(result.ok).toBe(false)
    expect(result.missing).toEqual(['slow.example.hu'])
  })
})
