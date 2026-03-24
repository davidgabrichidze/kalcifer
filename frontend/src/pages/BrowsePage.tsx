import { useState, useEffect, useCallback, useMemo } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import {
  fetchFlows, activateFlow, pauseFlow, archiveFlow,
  fetchInstances, fetchInstanceTimeline,
  type Flow, type FlowStatus, type FlowInstanceSummary, type ExecutionStepData,
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
        {panel === 'instances' && <InstancesPanel flows={flows} />}
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
  const navigate = useNavigate()
  const created = new Date(flow.inserted_at).toLocaleDateString('ka-GE')
  const updated = timeAgo(flow.updated_at)

  return (
    <tr>
      <td
        style={{ fontWeight: 500, color: 'var(--color-primary)', cursor: 'pointer' }}
        onClick={() => navigate(`/editor?flow=${flow.id}`)}
        title="ედიტორში გახსნა"
      >{flow.name}</td>
      <td><StatusTag status={flow.status} /></td>
      <td style={{ maxWidth: 200, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
        {flow.description || '—'}
      </td>
      <td>{created}</td>
      <td>{updated}</td>
      <td>
        <div style={{ display: 'flex', gap: 4 }}>
          <ActionBtn label="✎" title="ედიტორი" disabled={false} onClick={() => navigate(`/editor?flow=${flow.id}`)} />
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
// ── INSTANCES PANEL ─────────────────────────────────────
// ═══════════════════════════════════════════════════════════

const INSTANCE_STATUS_COLORS: Record<string, { bg: string; fg: string }> = {
  running: { bg: 'var(--color-info-soft)', fg: 'var(--color-info)' },
  waiting: { bg: 'var(--color-warn-soft)', fg: 'var(--color-warn)' },
  completed: { bg: 'var(--color-success-soft)', fg: 'var(--color-success)' },
  failed: { bg: 'var(--color-danger-soft)', fg: 'var(--color-danger)' },
  exited: { bg: 'var(--color-accent-soft)', fg: 'var(--color-text-muted)' },
  paused: { bg: 'var(--color-warn-soft)', fg: 'var(--color-warn)' },
}

function InstancesPanel({ flows }: { flows: Flow[] }) {
  const [selectedFlowId, setSelectedFlowId] = useState<string | null>(null)
  const [instances, setInstances] = useState<FlowInstanceSummary[]>([])
  const [loading, setLoading] = useState(false)
  const [selectedInstanceId, setSelectedInstanceId] = useState<string | null>(null)
  const [timeline, setTimeline] = useState<ExecutionStepData[]>([])
  const [timelineLoading, setTimelineLoading] = useState(false)

  // Auto-select first flow with instances
  useEffect(() => {
    if (flows.length > 0 && !selectedFlowId) {
      setSelectedFlowId(flows[0]!.id)
    }
  }, [flows, selectedFlowId])

  // Load instances when flow selected
  useEffect(() => {
    if (!selectedFlowId) return
    setLoading(true)
    setSelectedInstanceId(null)
    setTimeline([])
    fetchInstances(selectedFlowId, { limit: 50 })
      .then(data => { setInstances(data); setLoading(false) })
      .catch(() => { setInstances([]); setLoading(false) })
  }, [selectedFlowId])

  // Load timeline when instance selected
  useEffect(() => {
    if (!selectedInstanceId) return
    setTimelineLoading(true)
    fetchInstanceTimeline(selectedInstanceId)
      .then(data => { setTimeline(data); setTimelineLoading(false) })
      .catch(() => { setTimeline([]); setTimelineLoading(false) })
  }, [selectedInstanceId])

  return (
    <div>
      <div className="browse-page-head">
        <h2>Instances</h2>
        <p>ფლოუ ინსტანსები — ყოველი execution-ის ისტორია და timeline</p>
      </div>

      {/* Flow selector */}
      <div style={{ marginBottom: 12 }}>
        <select
          className="browse-select"
          value={selectedFlowId || ''}
          onChange={e => setSelectedFlowId(e.target.value || null)}
          style={{
            padding: '6px 10px', fontSize: 12, borderRadius: 6,
            border: '1px solid var(--color-border)', background: 'var(--color-surface)',
            color: 'var(--color-text)', minWidth: 200,
          }}
        >
          <option value="">— აირჩიე ფლოუ —</option>
          {flows.map(f => (
            <option key={f.id} value={f.id}>{f.name} ({f.status})</option>
          ))}
        </select>
        {instances.length > 0 && (
          <span style={{ marginLeft: 8, fontSize: 11, color: 'var(--color-text-muted)' }}>
            {instances.length} ინსტანსი
          </span>
        )}
      </div>

      {/* Instances table */}
      {loading ? (
        <div style={{ padding: 30, textAlign: 'center', color: 'var(--color-text-muted)', fontSize: 13 }}>
          იტვირთება...
        </div>
      ) : !selectedFlowId ? (
        <div style={{ padding: 30, textAlign: 'center', color: 'var(--color-text-muted)', fontSize: 13 }}>
          აირჩიეთ ფლოუ ინსტანსების სანახავად
        </div>
      ) : instances.length === 0 ? (
        <div style={{ padding: 30, textAlign: 'center', color: 'var(--color-text-muted)', fontSize: 13 }}>
          ინსტანსები ჯერ არ არის
        </div>
      ) : (
        <div style={{ display: 'flex', gap: 12 }}>
          {/* Instance list */}
          <div className="browse-card" style={{ padding: 0, overflow: 'hidden', flex: 1 }}>
            <table className="browse-table">
              <thead>
                <tr>
                  <th>ID</th>
                  <th>Customer</th>
                  <th>სტატუსი</th>
                  <th>Dry Run</th>
                  <th>დაწყება</th>
                  <th>დასრულება</th>
                </tr>
              </thead>
              <tbody>
                {instances.map(inst => {
                  const isSelected = inst.id === selectedInstanceId
                  const c = INSTANCE_STATUS_COLORS[inst.status] || INSTANCE_STATUS_COLORS.exited!
                  return (
                    <tr
                      key={inst.id}
                      onClick={() => setSelectedInstanceId(inst.id)}
                      style={{
                        cursor: 'pointer',
                        background: isSelected ? 'var(--color-primary-soft)' : undefined,
                      }}
                    >
                      <td style={{ fontFamily: 'var(--font-mono)', fontSize: 10 }}>
                        {inst.id.slice(0, 8)}...
                      </td>
                      <td style={{ fontSize: 11 }}>{inst.customer_id?.slice(0, 12) || '—'}</td>
                      <td>
                        <span className="browse-tag" style={{ background: c.bg, color: c.fg }}>
                          {inst.status}
                        </span>
                      </td>
                      <td>{inst.dry_run ? '✓' : ''}</td>
                      <td style={{ fontSize: 11 }}>{inst.entered_at ? timeAgo(inst.entered_at) : '—'}</td>
                      <td style={{ fontSize: 11 }}>{inst.completed_at ? timeAgo(inst.completed_at) : inst.exited_at ? timeAgo(inst.exited_at) : '—'}</td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>

          {/* Timeline panel */}
          {selectedInstanceId && (
            <div className="browse-card" style={{ width: 360, flexShrink: 0, overflow: 'auto', maxHeight: 500 }}>
              <div style={{ padding: '8px 12px', borderBottom: '1px solid var(--color-border)', fontSize: 12, fontWeight: 600 }}>
                Timeline
              </div>
              {timelineLoading ? (
                <div style={{ padding: 20, textAlign: 'center', fontSize: 12, color: 'var(--color-text-muted)' }}>
                  იტვირთება...
                </div>
              ) : timeline.length === 0 ? (
                <div style={{ padding: 20, textAlign: 'center', fontSize: 12, color: 'var(--color-text-muted)' }}>
                  Steps არ არის
                </div>
              ) : (
                <div style={{ padding: 8 }}>
                  {timeline.map((step, i) => (
                    <TimelineStep key={step.id} step={step} index={i} />
                  ))}
                </div>
              )}
            </div>
          )}
        </div>
      )}
    </div>
  )
}

function TimelineStep({ step, index }: { step: ExecutionStepData; index: number }) {
  const [expanded, setExpanded] = useState(false)
  const c = INSTANCE_STATUS_COLORS[step.status] || INSTANCE_STATUS_COLORS.exited!

  const duration =
    step.started_at && step.completed_at
      ? Math.round(new Date(step.completed_at).getTime() - new Date(step.started_at).getTime())
      : null

  return (
    <div style={{ marginBottom: 4 }}>
      <button
        onClick={() => setExpanded(!expanded)}
        style={{
          display: 'flex', alignItems: 'center', gap: 6, width: '100%',
          padding: '5px 8px', border: 'none', borderRadius: 6,
          background: expanded ? 'var(--color-surface-dim)' : 'transparent',
          cursor: 'pointer', fontSize: 11, color: 'var(--color-text)',
          textAlign: 'left',
        }}
      >
        <span style={{ width: 16, height: 16, borderRadius: '50%', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 9, fontWeight: 700, background: c.bg, color: c.fg, flexShrink: 0 }}>
          {index + 1}
        </span>
        <span style={{ flex: 1, fontWeight: 500 }}>{step.node_type}</span>
        <span style={{ fontSize: 9, color: 'var(--color-text-muted)', fontFamily: 'var(--font-mono)' }}>
          {step.node_id}
        </span>
        {duration !== null && (
          <span style={{ fontSize: 9, color: 'var(--color-text-muted)' }}>
            {duration < 1000 ? `${duration}ms` : `${(duration / 1000).toFixed(1)}s`}
          </span>
        )}
      </button>
      {expanded && step.output && (
        <pre style={{
          margin: '2px 0 4px 24px', padding: '4px 8px', borderRadius: 4,
          background: 'var(--color-surface-dim)', fontSize: 10, overflow: 'auto',
          maxHeight: 150, color: 'var(--color-text-sec)', fontFamily: 'var(--font-mono)',
        }}>
          {JSON.stringify(step.output, null, 2)}
        </pre>
      )}
      {expanded && step.error && (
        <pre style={{
          margin: '2px 0 4px 24px', padding: '4px 8px', borderRadius: 4,
          background: 'var(--color-danger-soft)', fontSize: 10, overflow: 'auto',
          maxHeight: 100, color: 'var(--color-danger)', fontFamily: 'var(--font-mono)',
        }}>
          {JSON.stringify(step.error, null, 2)}
        </pre>
      )}
    </div>
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
