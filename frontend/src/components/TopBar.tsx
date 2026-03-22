import { NavLink } from 'react-router-dom'
import { type ThemeId } from '../lib/themes'
import ThemeSwitcher from './ThemeSwitcher'

interface TopBarProps {
  theme: ThemeId
  onThemeChange: (id: ThemeId) => void
}

const NAV_ITEMS = [
  { to: '/', label: 'Work' },
  { to: '/browse', label: 'Browse' },
  { to: '/engine', label: 'Engine Room' },
] as const

export default function TopBar({ theme, onThemeChange }: TopBarProps) {
  return (
    <header
      className="flex shrink-0 items-center justify-between"
      style={{
        height: 48,
        background: 'var(--color-surface)',
        borderBottom: '1px solid var(--color-border)',
        padding: '0 16px',
      }}
    >
      {/* Left: Logo */}
      <div className="flex items-center" style={{ gap: 14 }}>
        <span
          className="cursor-pointer font-bold"
          style={{
            fontSize: 17,
            color: 'var(--color-primary)',
            letterSpacing: '-0.5px',
          }}
        >
          Kalcifer
        </span>
      </div>

      {/* Center: Main nav */}
      <nav className="flex items-center" style={{ gap: 4 }}>
        {NAV_ITEMS.map(({ to, label }) => (
          <NavLink
            key={to}
            to={to}
            style={({ isActive }) => ({
              height: 30,
              padding: '0 10px',
              borderRadius: 6,
              fontSize: 11,
              fontFamily: 'inherit',
              fontWeight: 500,
              display: 'flex',
              alignItems: 'center',
              gap: 4,
              cursor: 'pointer',
              transition: 'all 0.2s',
              border: isActive
                ? '1px solid var(--color-primary)'
                : '1px solid var(--color-border)',
              background: isActive
                ? 'var(--color-primary)'
                : 'var(--color-surface-dim)',
              color: isActive
                ? 'var(--color-text-on-primary)'
                : 'var(--color-text-sec)',
            })}
          >
            {label}
          </NavLink>
        ))}
      </nav>

      {/* Right: Theme switcher */}
      <div className="flex items-center" style={{ gap: 6 }}>
        <ThemeSwitcher current={theme} onChange={onThemeChange} />
      </div>
    </header>
  )
}
