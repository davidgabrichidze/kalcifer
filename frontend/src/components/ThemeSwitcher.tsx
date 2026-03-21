import { THEMES, type ThemeId } from '../lib/themes'

interface ThemeSwitcherProps {
  current: ThemeId
  onChange: (id: ThemeId) => void
}

const PALETTE_COLORS: Record<string, { light: string; dark: string }> = {
  hearth:   { light: '#c07a3e', dark: '#e0a060' },
  command:  { light: '#4a5eb0', dark: '#8090e0' },
  grove:    { light: '#4a8a5a', dark: '#6cc480' },
  calcifer: { light: '#c07838', dark: '#e09848' },
}

export default function ThemeSwitcher({ current, onChange }: ThemeSwitcherProps) {
  return (
    <div
      className="flex gap-1.5"
    >
      {THEMES.map(t => {
        const color = PALETTE_COLORS[t.palette]?.[t.mode] ?? '#888'
        const isActive = current === t.id
        const isDark = t.mode === 'dark'

        return (
          <button
            key={t.id}
            onClick={() => onChange(t.id)}
            title={`${t.label} ${t.mode}`}
            className="relative flex h-6 w-6 items-center justify-center rounded-md transition-transform hover:scale-110"
            style={{
              background: isDark ? '#1a1a1a' : '#f5f5f0',
              border: isActive
                ? `2px solid ${color}`
                : '2px solid transparent',
              outline: isActive ? `2px solid ${color}33` : 'none',
              outlineOffset: '1px',
            }}
          >
            <div
              className="h-2.5 w-2.5 rounded-full"
              style={{ background: color }}
            />
          </button>
        )
      })}
    </div>
  )
}
