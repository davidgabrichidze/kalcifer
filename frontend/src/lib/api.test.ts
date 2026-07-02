import { afterEach, describe, expect, it, vi } from 'vitest'
import { fetchTenants, parseNodeWarnings, setActiveTenantId, setAuthToken } from './api'

describe('apiFetch auth injection', () => {
  afterEach(() => {
    setAuthToken(null)
    setActiveTenantId(null)
    vi.restoreAllMocks()
  })

  function stubFetch() {
    const spy = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ data: [] }),
    } as Response)
    vi.stubGlobal('fetch', spy)
    return spy
  }

  it('adds the Bearer token to every request when signed in', async () => {
    const spy = stubFetch()
    setAuthToken('tok-123')

    await fetchTenants()

    const headers = (spy.mock.calls[0]![1] as RequestInit).headers as Headers
    expect(headers.get('Authorization')).toBe('Bearer tok-123')
  })

  it('adds the tenant header when a tenant is selected', async () => {
    const spy = stubFetch()
    setActiveTenantId('tenant-abc')

    await fetchTenants()

    const headers = (spy.mock.calls[0]![1] as RequestInit).headers as Headers
    expect(headers.get('X-Tenant-Id')).toBe('tenant-abc')
  })

  it('omits auth headers when neither token nor tenant is set', async () => {
    const spy = stubFetch()

    await fetchTenants()

    const headers = (spy.mock.calls[0]![1] as RequestInit).headers as Headers
    expect(headers.get('Authorization')).toBeNull()
    expect(headers.get('X-Tenant-Id')).toBeNull()
  })
})

describe('parseNodeWarnings', () => {
  it('parses node warnings from preflight format', () => {
    const warnings = [
      'node email_1 (send_email): missing required field "template"',
      'node email_1 (send_email): missing required field "subject"',
      'node wait_2 (wait): missing required field "duration"',
    ]
    const result = parseNodeWarnings(warnings)

    expect(result.size).toBe(2)
    expect(result.get('email_1')).toEqual([
      'missing required field "template"',
      'missing required field "subject"',
    ])
    expect(result.get('wait_2')).toEqual([
      'missing required field "duration"',
    ])
  })

  it('returns empty map for no warnings', () => {
    expect(parseNodeWarnings([]).size).toBe(0)
  })

  it('skips non-matching warning formats', () => {
    const warnings = [
      'graph must have at least one entry node',
      'node abc_1 (condition): missing field',
    ]
    const result = parseNodeWarnings(warnings)
    expect(result.size).toBe(1)
    expect(result.has('abc_1')).toBe(true)
  })
})
