import { describe, it, expect, beforeEach } from 'vitest'
import { THEMES, DEFAULT_THEME, applyTheme, getStoredTheme, storeTheme } from './themes'

describe('themes', () => {
  it('has 8 themes (4 palettes × 2 modes)', () => {
    expect(THEMES).toHaveLength(8)
  })

  it('every theme has light and dark mode', () => {
    const palettes = [...new Set(THEMES.map(t => t.palette))]
    expect(palettes).toHaveLength(4)

    for (const palette of palettes) {
      const modes = THEMES.filter(t => t.palette === palette).map(t => t.mode)
      expect(modes).toContain('light')
      expect(modes).toContain('dark')
    }
  })

  it('default theme is hearth-light', () => {
    expect(DEFAULT_THEME).toBe('hearth-light')
  })

  describe('applyTheme', () => {
    it('sets data-theme attribute on body', () => {
      applyTheme('command-dark')
      expect(document.body.getAttribute('data-theme')).toBe('command-dark')
    })
  })

  describe('storeTheme / getStoredTheme', () => {
    beforeEach(() => {
      localStorage.clear()
    })

    it('returns default when nothing stored', () => {
      expect(getStoredTheme()).toBe(DEFAULT_THEME)
    })

    it('round-trips a theme', () => {
      storeTheme('grove-dark')
      expect(getStoredTheme()).toBe('grove-dark')
    })

    it('returns default for invalid stored value', () => {
      localStorage.setItem('kalcifer-theme', 'nonsense')
      expect(getStoredTheme()).toBe(DEFAULT_THEME)
    })
  })
})
