// APPROVALFLOOR916: store/autonomy-config.json carries `timeout_minutes` per
// category, and the approval route reads it as the MINIMUM deadline for that
// category. The field lives in a gitignored per-install file and is written by
// hand, so nothing in the repo would notice if this route started dropping it.
//
// Two ways it could vanish, both silent:
//   (1) the GET stops passing the field through to the dashboard, so the owner
//       inspects /api/autonomy, sees no deadline, and concludes there is none
//       (this is exactly the wrong conclusion that started this work), or
//   (2) the POST rebuilds the category object instead of mutating it, and the
//       level change quietly erases the deadline.
//
// These are string contracts, the house idiom for route wiring
// (see approvals-prompt-contract.test.ts).
import { describe, it, expect } from 'vitest'
import { readFileSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const ROUTE = readFileSync(join(__dirname, '../../src/web/routes/autonomy.ts'), 'utf-8')

describe('autonomy route keeps the category deadline visible and intact', () => {
  it('the category type declares timeout_minutes', () => {
    expect(ROUTE).toMatch(/timeout_minutes\?\s*:\s*number\s*\|\s*null/)
  })

  it('GET returns the whole config, so the deadline is inspectable', () => {
    // A hand-built response would be where the field goes missing.
    expect(ROUTE).toContain('json(res, config)')
  })

  it('the level update MUTATES the category, it does not rebuild it', () => {
    // `cat.level = level` preserves every other field, including the deadline.
    expect(ROUTE).toContain('cat.level = level')
    // A spread-rebuild would drop unknown fields; assert nobody introduced one.
    expect(ROUTE).not.toMatch(/categories\s*=\s*config\.categories\.map\(/)
  })

  it('saveConfig writes the loaded object back, not a reduced copy', () => {
    expect(ROUTE).toContain('JSON.stringify(config, null, 2)')
  })
})
