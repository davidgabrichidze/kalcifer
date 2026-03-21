import { NavLink } from 'react-router-dom'
import { type ThemeId } from '../lib/themes'
import ThemeSwitcher from './ThemeSwitcher'

interface TopBarProps {
  theme: ThemeId
  onThemeChange: (id: ThemeId) => void
}

const NAV_ITEMS = [
  { to: '/', label: 'Work' },
  { to: '/engine', label: 'Engine Room' },
  { to: '/browse', label: 'Browse' },
] as const

export default function TopBar({ theme, onThemeChange }: TopBarProps) {
  return (
    <header
      className="flex h-14 shrink-0 items-center justify-between px-5"
      style={{
        background: 'var(--color-surface)',
        borderBottom: '1px solid var(--color-border)',
      }}
    >
      <div className="flex items-center gap-6">
        <span
          className="text-lg font-bold tracking-tight"
          style={{ color: 'var(--color-primary)' }}
        >
          🔥 Kalcifer
        </span>

        <nav className="flex gap-1">
          {NAV_ITEMS.map(({ to, label }) => (
            <NavLink
              key={to}
              to={to}
              className="rounded-lg px-3 py-1.5 text-sm font-medium transition-colors"
              style={({ isActive }) => ({
                color: isActive ? 'var(--color-primary)' : 'var(--color-text-sec)',
                background: isActive ? 'var(--color-primary-soft)' : 'transparent',
              })}
            >
              {label}
            </NavLink>
          ))}
        </nav>
      </div>

      <ThemeSwitcher current={theme} onChange={onThemeChange} />
    </header>
  )
}
