import { useEffect, useRef, useState } from 'react'
import {
  fetchTenants,
  getActiveTenantId,
  setActiveTenantId,
  type TenantSummary,
} from '../lib/api'

/**
 * Dev tenant switcher: lists tenants and pins the chosen one via the
 * X-Tenant-Id header on all API calls (persisted in localStorage).
 */
export default function TenantSwitcher() {
  const [open, setOpen] = useState(false)
  const [tenants, setTenants] = useState<TenantSummary[]>([])
  const wrapRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    fetchTenants()
      .then(setTenants)
      .catch(() => setTenants([]))
  }, [])

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

  if (tenants.length < 2) return null

  const storedId = getActiveTenantId()
  const active =
    tenants.find(t => t.id === storedId) || tenants.find(t => t.active) || tenants[0]

  const switchTenant = (id: string) => {
    setActiveTenantId(id)
    setOpen(false)
    window.location.reload()
  }

  return (
    <div ref={wrapRef} style={{ position: 'relative' }}>
      <button
        onClick={() => setOpen(o => !o)}
        title="Switch tenant"
        style={{
          height: 30,
          padding: '0 10px',
          borderRadius: 6,
          display: 'flex',
          alignItems: 'center',
          gap: 6,
          fontSize: 11,
          fontWeight: 500,
          cursor: 'pointer',
          border: '1px solid var(--color-border)',
          background: 'var(--color-surface-dim)',
          color: 'var(--color-text-sec)',
          transition: 'all 0.2s',
        }}
      >
        <span style={{ opacity: 0.6 }}>◫</span>
        {active?.name || 'Tenant'}
      </button>

      {open && (
        <div
          style={{
            position: 'absolute',
            top: 36,
            right: 0,
            minWidth: 180,
            background: 'var(--color-surface)',
            border: '1px solid var(--color-border)',
            borderRadius: 8,
            padding: 4,
            zIndex: 100,
            boxShadow: '0 4px 16px rgba(0,0,0,0.15)',
          }}
        >
          {tenants.map(tenant => (
            <button
              key={tenant.id}
              onClick={() => switchTenant(tenant.id)}
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: 8,
                width: '100%',
                padding: '6px 10px',
                borderRadius: 6,
                border: 'none',
                background:
                  tenant.id === active?.id ? 'var(--color-surface-dim)' : 'transparent',
                color: 'var(--color-text)',
                fontSize: 11,
                textAlign: 'left',
                cursor: 'pointer',
              }}
            >
              <span style={{ width: 12 }}>{tenant.id === active?.id ? '✓' : ''}</span>
              {tenant.name}
            </button>
          ))}
        </div>
      )}
    </div>
  )
}
