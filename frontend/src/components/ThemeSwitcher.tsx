import { useState, useRef, useEffect } from 'react'
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
  const [open, setOpen] = useState(false)
  const wrapRef = useRef<HTMLDivElement>(null)

  // Close on outside click
  useEffect(() => {
    if (!open) return
    function handleClick(e: MouseEvent) {
      if (wrapRef.current && !wrapRef.current.contains(e.target as Node)) {
        setOpen(false)
      }
    }
    document.addEventListener('mousedown', handleClick)
    return () => document.removeEventListener('mousedown', handleClick)
  }, [open])

  return (
    <div ref={wrapRef} style={{ position: 'relative' }}>
      <button
        onClick={() => setOpen(o => !o)}
        title="Theme"
        style={{
          height: 30,
          width: 30,
          borderRadius: 6,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          fontSize: 14,
          cursor: 'pointer',
          border: '1px solid var(--color-border)',
          background: 'var(--color-surface-dim)',
          color: 'var(--color-text-sec)',
          transition: 'all 0.2s',
        }}
      >
        ◔
      </button>

      {open && (
        <div
          style={{
            position: 'absolute',
            top: 36,
            right: 0,
            background: 'var(--color-surface)',
            border: '1px solid var(--color-border)',
            borderRadius: 10,
            padding: 4,
            boxShadow: 'var(--shadow-md)',
            zIndex: 500,
            minWidth: 160,
          }}
        >
          {THEMES.map(t => {
            const color = PALETTE_COLORS[t.palette]?.[t.mode] ?? '#888'
            const isActive = current === t.id

            return (
              <button
                key={t.id}
                onClick={() => { onChange(t.id); setOpen(false) }}
                title={`${t.label} ${t.mode}`}
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  gap: 8,
                  padding: '6px 8px',
                  borderRadius: 6,
                  cursor: 'pointer',
                  fontSize: 11,
                  fontFamily: 'inherit',
                  color: isActive ? 'var(--color-text)' : 'var(--color-text-sec)',
                  background: isActive ? 'var(--color-primary-soft)' : 'transparent',
                  border: 'none',
                  width: '100%',
                  transition: 'all 0.15s',
                }}
              >
                <span style={{ display: 'flex', gap: 3 }}>
                  <span
                    style={{
                      width: 14,
                      height: 14,
                      borderRadius: 4,
                      background: t.mode === 'dark' ? '#1a1a1a' : '#f5f5f0',
                      border: '1px solid var(--color-border-light)',
                      display: 'inline-flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                    }}
                  >
                    <span
                      style={{
                        width: 8,
                        height: 8,
                        borderRadius: '50%',
                        background: color,
                      }}
                    />
                  </span>
                </span>
                {t.label} {t.mode === 'dark' ? 'Dark' : ''}
              </button>
            )
          })}
        </div>
      )}
    </div>
  )
}
