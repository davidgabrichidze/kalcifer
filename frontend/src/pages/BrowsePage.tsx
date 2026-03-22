import { useState, useEffect, useCallback, useMemo } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import {
  fetchFlows, activateFlow, pauseFlow, archiveFlow,
  type Flow, type FlowStatus,
} from '../lib/api'

// ── Nav ──────────────────────────────────────────────────

type PanelId = 'flows' | 'journeys' | 'instances' | 'events' | 'analytics'

const NAV_ITEMS: { id: PanelId; icon: string; text: string }[] = [
  { id: 'flows', icon: '⇄', text: 'Flows' },
  { id: 'instances', icon: '▶', text: 'Instances' },
  { id: 'events', icon: '⚡', text: 'Events' },
  { id: 'journeys', icon: '☰', text: 'Journeys' },
  { id: 'analytics', icon: '△', text: 'Analytics' },
]

const VALID_PANELS: PanelId[] = NAV_ITEMS.map(i => i.id)

function panelFromHash(hash: string): PanelId {
  const id = hash.replace('#', '') as PanelId
  return VALID_PANELS.includes(id) ? id : 'flows'
}

// ── Main Component ───────────────────────────────────────

export default function BrowsePage() {
  const location = useLocation()
  const navigate = useNavigate()
  const initialPanel = useMemo(() => panelFromHash(location.hash), []) // eslint-disable-line react-hooks/exhaustive-deps
  const [panel, _setPanel] = useState<PanelId>(initialPanel)

  const setPanel = useCallback((id: PanelId) => {
    _setPanel(id)
    navigate(`/browse#${id}`, { replace: true })
  }, [navigate])

  // ── Flows data ──
  const [flows, setFlows] = useState<Flow[]>([])
  const [flowsLoading, setFlowsLoading] = useState(true)

  const loadFlows = useCallback(() => {
    fetchFlows().then(f => { setFlows(f); setFlowsLoading(false) }).catch(() => setFlowsLoading(false))
  }, [])

  useEffect(() => { loadFlows() }, [loadFlows])

  // ── Nav badges ──
  const navBadge = (id: PanelId): string | null => {
    switch (id) {
      case 'flows': return flows.length ? String(flows.length) : null
      default: return null
    }
  }

  return (
    <div className="browse-shell">
      {/* Left nav */}
      <div className="browse-nav">
        <div className="browse-nav-scroll">
          {NAV_ITEMS.map(item => (
            <button
              key={item.id}
              className={`browse-nav-item ${panel === item.id ? 'active' : ''}`}
              onClick={() => setPanel(item.id)}
            >
              <span className="browse-nav-icon">{item.icon}</span>
              <span className="browse-nav-text">{item.text}</span>
              {navBadge(item.id) && (
                <span className="browse-nav-badge">{navBadge(item.id)}</span>
              )}
            </button>
          ))}
        </div>
      </div>

      {/* Content */}
      <div className="browse-content">
        {panel === 'flows' && (
          <FlowsPanel flows={flows} loading={flowsLoading} onReload={loadFlows} />
        )}
        {panel === 'instances' && <ComingSoon label="Instances" />}
        {panel === 'events' && <ComingSoon label="Events" />}
        {panel === 'journeys' && <ComingSoon label="Journeys" />}
        {panel === 'analytics' && <ComingSoon label="Analytics" />}
      </div>
    </div>
  )
}

// ═══════════════════════════════════════════════════════════
// ── FLOWS PANEL ──────────────────────────────────────────
// ═══════════════════════════════════════════════════════════

const STATUS_TABS: { value: FlowStatus | 'all'; label: string }[] = [
  { value: 'all', label: 'ყველა' },
  { value: 'active', label: 'Active' },
  { value: 'draft', label: 'Draft' },
  { value: 'paused', label: 'Paused' },
  { value: 'archived', label: 'Archived' },
]

function FlowsPanel({
  flows, loading, onReload,
}: {
  flows: Flow[]
  loading: boolean
  onReload: () => void
}) {
  const [filter, setFilter] = useState<FlowStatus | 'all'>('all')
  const [actionLoading, setActionLoading] = useState<string | null>(null)

  const filtered = filter === 'all' ? flows : flows.filter(f => f.status === filter)
  const statusCounts = flows.reduce((acc, f) => {
    acc[f.status] = (acc[f.status] || 0) + 1
    return acc
  }, {} as Record<string, number>)

  const handleAction = async (id: string, action: 'activate' | 'pause' | 'archive') => {
    setActionLoading(id)
    try {
      const fn = action === 'activate' ? activateFlow : action === 'pause' ? pauseFlow : archiveFlow
      await fn(id)
      onReload()
    } catch {
      // TODO: toast
    } finally {
      setActionLoading(null)
    }
  }

  return (
    <div>
      <div className="browse-page-head">
        <h2>Flows</h2>
        <p>ფლოუების ბიბლიოთეკა — შექმნა, მართვა, სტატუსის ცვლილება</p>
      </div>

      {/* Status filter tabs */}
      <div className="browse-tabs">
        {STATUS_TABS.map(tab => {
          const count = tab.value === 'all' ? flows.length : (statusCounts[tab.value] || 0)
          return (
            <button
              key={tab.value}
              className={`browse-tab ${filter === tab.value ? 'browse-tab-active' : ''}`}
              onClick={() => setFilter(tab.value)}
            >
              {tab.label}
              <span className="browse-tab-count">{count}</span>
            </button>
          )
        })}
      </div>

      {/* Table */}
      {loading ? (
        <div style={{ padding: 40, textAlign: 'center', color: 'var(--color-text-muted)', fontSize: 13 }}>
          იტვირთება...
        </div>
      ) : filtered.length === 0 ? (
        <div style={{ padding: 40, textAlign: 'center', color: 'var(--color-text-muted)', fontSize: 13 }}>
          {filter === 'all' ? 'ფლოუები ჯერ არ არის' : `${filter} ფლოუები არ არის`}
        </div>
      ) : (
        <div className="browse-card" style={{ padding: 0, overflow: 'hidden' }}>
          <table className="browse-table">
            <thead>
              <tr>
                <th>სახელი</th>
                <th>სტატუსი</th>
                <th>აღწერა</th>
                <th>შექმნილი</th>
                <th>განახლებული</th>
                <th style={{ width: 80 }}>მოქმედება</th>
              </tr>
            </thead>
            <tbody>
              {filtered.map(flow => (
                <FlowRow
                  key={flow.id}
                  flow={flow}
                  loading={actionLoading === flow.id}
                  onAction={handleAction}
                />
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}

function FlowRow({
  flow, loading, onAction,
}: {
  flow: Flow
  loading: boolean
  onAction: (id: string, action: 'activate' | 'pause' | 'archive') => void
}) {
  const created = new Date(flow.inserted_at).toLocaleDateString('ka-GE')
  const updated = timeAgo(flow.updated_at)

  return (
    <tr>
      <td style={{ fontWeight: 500, color: 'var(--color-text)' }}>{flow.name}</td>
      <td><StatusTag status={flow.status} /></td>
      <td style={{ maxWidth: 200, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
        {flow.description || '—'}
      </td>
      <td>{created}</td>
      <td>{updated}</td>
      <td>
        <div style={{ display: 'flex', gap: 4 }}>
          {flow.status === 'draft' && (
            <ActionBtn label="▶" title="გააქტიურება" disabled={loading} onClick={() => onAction(flow.id, 'activate')} />
          )}
          {flow.status === 'active' && (
            <ActionBtn label="⏸" title="პაუზა" disabled={loading} onClick={() => onAction(flow.id, 'pause')} />
          )}
          {flow.status === 'paused' && (
            <>
              <ActionBtn label="▶" title="გააქტიურება" disabled={loading} onClick={() => onAction(flow.id, 'activate')} />
              <ActionBtn label="📦" title="არქივი" disabled={loading} onClick={() => onAction(flow.id, 'archive')} />
            </>
          )}
          {flow.status === 'active' && (
            <ActionBtn label="📦" title="არქივი" disabled={loading} onClick={() => onAction(flow.id, 'archive')} />
          )}
        </div>
      </td>
    </tr>
  )
}

function ActionBtn({ label, title, disabled, onClick }: { label: string; title: string; disabled: boolean; onClick: () => void }) {
  return (
    <button
      className="browse-action-btn"
      title={title}
      disabled={disabled}
      onClick={e => { e.stopPropagation(); onClick() }}
    >
      {label}
    </button>
  )
}

function StatusTag({ status }: { status: string }) {
  const map: Record<string, { color: string; label: string }> = {
    active: { color: 'green', label: 'Active' },
    draft: { color: 'blue', label: 'Draft' },
    paused: { color: 'orange', label: 'Paused' },
    archived: { color: 'muted', label: 'Archived' },
  }
  const s = map[status] || { color: 'muted', label: status }
  const colors: Record<string, { bg: string; fg: string }> = {
    green: { bg: 'var(--color-success-soft)', fg: 'var(--color-success)' },
    blue: { bg: 'var(--color-info-soft)', fg: 'var(--color-info)' },
    orange: { bg: 'var(--color-warn-soft)', fg: 'var(--color-warn)' },
    muted: { bg: 'var(--color-accent-soft)', fg: 'var(--color-text-muted)' },
  }
  const c = colors[s.color] ?? colors.muted!
  return (
    <span className="browse-tag" style={{ background: c!.bg, color: c!.fg }}>{s.label}</span>
  )
}

// ═══════════════════════════════════════════════════════════
// ── SHARED ───────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════

function ComingSoon({ label }: { label: string }) {
  return (
    <div style={{ padding: 60, textAlign: 'center' }}>
      <div style={{ fontSize: 28, marginBottom: 8, opacity: 0.3 }}>🚧</div>
      <div style={{ fontSize: 14, fontWeight: 600, color: 'var(--color-text)' }}>{label}</div>
      <div style={{ fontSize: 12, color: 'var(--color-text-muted)', marginTop: 4 }}>მალე</div>
    </div>
  )
}

function timeAgo(iso: string): string {
  const diff = Date.now() - new Date(iso).getTime()
  const mins = Math.floor(diff / 60_000)
  if (mins < 1) return 'ახლახან'
  if (mins < 60) return `${mins} წთ-ის წინ`
  const hours = Math.floor(mins / 60)
  if (hours < 24) return `${hours} სთ-ის წინ`
  const days = Math.floor(hours / 24)
  if (days < 30) return `${days} დღის წინ`
  return new Date(iso).toLocaleDateString('ka-GE')
}
