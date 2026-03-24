import { describe, it, expect } from 'vitest'
import { parseNodeWarnings } from './api'

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
