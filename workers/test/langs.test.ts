import { describe, expect, it } from 'vitest'
import { parseOutputLangs } from '../src/lib/langs'

describe('parseOutputLangs', () => {
  it('parses, trims, lowercases, and drops blanks', () => {
    expect(parseOutputLangs(' ES , Fr , ,ja ')).toEqual(['es', 'fr', 'ja'])
  })
  it('returns [] for undefined', () => {
    expect(parseOutputLangs(undefined)).toEqual([])
  })
})
