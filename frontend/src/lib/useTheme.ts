import { useState, useEffect } from 'react'
import { type ThemeId, applyTheme, getStoredTheme, storeTheme } from './themes'

export function useTheme() {
  const [theme, setThemeState] = useState<ThemeId>(getStoredTheme)

  useEffect(() => {
    applyTheme(theme)
  }, [theme])

  function setTheme(id: ThemeId) {
    setThemeState(id)
    storeTheme(id)
    applyTheme(id)
  }

  return { theme, setTheme } as const
}
