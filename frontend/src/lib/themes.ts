export type ThemeId =
  | 'hearth-light' | 'hearth-dark'
  | 'command-light' | 'command-dark'
  | 'grove-light' | 'grove-dark'
  | 'calcifer-light' | 'calcifer-dark'

export interface ThemeMeta {
  id: ThemeId
  label: string
  palette: string
  mode: 'light' | 'dark'
}

export const THEMES: ThemeMeta[] = [
  { id: 'hearth-light', label: 'Hearth', palette: 'hearth', mode: 'light' },
  { id: 'hearth-dark', label: 'Hearth', palette: 'hearth', mode: 'dark' },
  { id: 'command-light', label: 'Command', palette: 'command', mode: 'light' },
  { id: 'command-dark', label: 'Command', palette: 'command', mode: 'dark' },
  { id: 'grove-light', label: 'Grove', palette: 'grove', mode: 'light' },
  { id: 'grove-dark', label: 'Grove', palette: 'grove', mode: 'dark' },
  { id: 'calcifer-light', label: 'Calcifer', palette: 'calcifer', mode: 'light' },
  { id: 'calcifer-dark', label: 'Calcifer', palette: 'calcifer', mode: 'dark' },
]

export const DEFAULT_THEME: ThemeId = 'hearth-light'

export function applyTheme(id: ThemeId): void {
  document.body.setAttribute('data-theme', id)
}

export function getStoredTheme(): ThemeId {
  try {
    const stored = localStorage.getItem('kalcifer-theme')
    if (stored && THEMES.some(t => t.id === stored)) {
      return stored as ThemeId
    }
  } catch {
    // localStorage unavailable
  }
  return DEFAULT_THEME
}

export function storeTheme(id: ThemeId): void {
  try {
    localStorage.setItem('kalcifer-theme', id)
  } catch {
    // localStorage unavailable
  }
}
