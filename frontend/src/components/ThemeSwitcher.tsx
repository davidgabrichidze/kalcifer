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
      className="fixed bottom-6 right-6 flex gap-2 rounded-xl p-3"
      style={{
        background: 'var(--color-surface)',
        border: '1px solid var(--color-border)',
        boxShadow: 'var(--shadow-md)',
      }}
    >
      {THEMES.map(t => {
        const color = PALETTE_COLORS[t.palette][t.mode]
        const isActive = current === t.id
        const isDark = t.mode === 'dark'

        return (
          <button
            key={t.id}
            onClick={() => onChange(t.id)}
            title={`${t.label} ${t.mode}`}
            className="relative flex h-8 w-8 items-center justify-center rounded-lg transition-transform hover:scale-110"
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
              className="h-3.5 w-3.5 rounded-full"
              style={{ background: color }}
            />
          </button>
        )
      })}
    </div>
  )
}
