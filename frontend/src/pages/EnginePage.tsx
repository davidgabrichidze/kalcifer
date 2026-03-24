import { useState, useEffect, useCallback, useMemo } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import {
  fetchSettings, updateSettings, fetchStats, fetchEngine, regenerateApiKey,
  type Settings, type Stats, type EngineData, type LogEntry,
} from '../lib/api'

// ── Nav items ───────────────────────────────────────────

type PanelId = 'ai' | 'channels' | 'registry' | 'oban' | 'health'

const NAV_SECTIONS = [
  {
    label: 'Configuration',
    items: [
      { id: 'ai' as PanelId, icon: '🤖', text: 'AI Config', badge: null },
      { id: 'channels' as PanelId, icon: '📡', text: 'Channels', badge: null },
    ],
  },
  {
    label: 'Engine',
    items: [
      { id: 'registry' as PanelId, icon: '⚙', text: 'Node Registry', badge: null },
      { id: 'oban' as PanelId, icon: '📋', text: 'Oban Queues', badge: null },
      { id: 'health' as PanelId, icon: '💚', text: 'System Health', badge: null },
    ],
  },
]

// ── Category color mapping ──────────────────────────────

const VALID_PANELS: PanelId[] = ['ai', 'channels', 'registry', 'oban', 'health']

function panelFromHash(hash: string): PanelId {
  const id = hash.replace('#', '') as PanelId
  return VALID_PANELS.includes(id) ? id : 'ai'
}

// ── Main Component ──────────────────────────────────────

export default function EnginePage() {
  const location = useLocation()
  const navigate = useNavigate()
  const initialPanel = useMemo(() => panelFromHash(location.hash), []) // eslint-disable-line react-hooks/exhaustive-deps
  const [panel, _setPanel] = useState<PanelId>(initialPanel)

  const setPanel = useCallback((id: PanelId) => {
    _setPanel(id)
    navigate(`/engine#${id}`, { replace: true })
  }, [navigate])
  const [settings, setSettings] = useState<Settings | null>(null)
  const [stats, setStats] = useState<Stats | null>(null)
  const [engine, setEngine] = useState<EngineData | null>(null)
  const [saving, setSaving] = useState(false)
  const [message, setMessage] = useState<{ text: string; type: 'ok' | 'err' } | null>(null)

  const loadAll = useCallback(() => {
    fetchSettings().then(setSettings).catch(() => {})
    fetchStats().then(setStats).catch(() => {})
    fetchEngine().then(setEngine).catch(() => {})
  }, [])

  useEffect(() => {
    loadAll()
    const interval = setInterval(loadAll, 15_000)
    return () => clearInterval(interval)
  }, [loadAll])

  useEffect(() => {
    if (!message) return
    const t = setTimeout(() => setMessage(null), 3000)
    return () => clearTimeout(t)
  }, [message])

  const toast = (text: string, type: 'ok' | 'err') => setMessage({ text, type })

  const handleModelChange = async (model: string) => {
    setSaving(true)
    try {
      const updated = await updateSettings({ ai_model: model })
      setSettings(updated)
      toast('მოდელი შეიცვალა', 'ok')
    } catch (e: any) {
      toast(e.message, 'err')
    } finally {
      setSaving(false)
    }
  }

  const handleSaveProviderKey = async (provider: string, key: string) => {
    setSaving(true)
    try {
      const updated = await updateSettings({ provider_key: { provider, key } })
      setSettings(updated)
      toast(`${provider} დაკავშირდა`, 'ok')
    } catch (e: any) {
      toast(e.message, 'err')
    } finally {
      setSaving(false)
    }
  }

  const handleRemoveProviderKey = async (provider: string) => {
    setSaving(true)
    try {
      const updated = await updateSettings({ remove_provider_key: provider })
      setSettings(updated)
      toast(`${provider} გათიშულია`, 'ok')
    } catch (e: any) {
      toast(e.message, 'err')
    } finally {
      setSaving(false)
    }
  }

  // Dynamic nav badges
  const navBadge = (id: PanelId): string | null => {
    if (!engine) return null
    switch (id) {
      case 'registry': return String(engine.node_registry.total)
      case 'oban': return String(engine.oban.queues.length)
      default: return null
    }
  }

  return (
    <div className="engine-shell">
      {/* ── LEFT NAV ── */}
      <div className="engine-nav">
        <div className="engine-nav-scroll">
          {NAV_SECTIONS.map(section => (
            <div key={section.label}>
              <div className="engine-nav-label">{section.label}</div>
              {section.items.map(item => (
                <button
                  key={item.id}
                  className={`engine-nav-item ${panel === item.id ? 'active' : ''}`}
                  onClick={() => setPanel(item.id)}
                >
                  <span className="engine-nav-icon">{item.icon}</span>
                  <span className="engine-nav-text">{item.text}</span>
                  {navBadge(item.id) && (
                    <span className="engine-nav-badge">{navBadge(item.id)}</span>
                  )}
                </button>
              ))}
            </div>
          ))}
        </div>
        <div className="engine-nav-bottom">
          <div className="engine-health-bar">
            <div className="engine-health-dot" />
            {engine ? (
              <span>Engine Healthy · OTP {engine.vm.otp_release}</span>
            ) : (
              <span>Connecting...</span>
            )}
          </div>
        </div>
      </div>

      {/* ── CONTENT AREA ── */}
      <div className="engine-content">
        {panel === 'ai' && (
          <AIConfigPanel
            settings={settings}
            stats={stats}
            saving={saving}
            onModelChange={handleModelChange}
            onSaveProviderKey={handleSaveProviderKey}
            onRemoveProviderKey={handleRemoveProviderKey}
          />
        )}
        {panel === 'channels' && (
          <ChannelsPanel
            providers={settings?.channel_providers || []}
            saving={saving}
            onUpdate={async (channel: string, provider: string) => {
              setSaving(true)
              try {
                const updated = await updateSettings({
                  channel_provider: { channel, provider }
                })
                setSettings(updated)
                setMessage({ text: `${channel} → ${provider}`, type: 'ok' })
              } catch (e: any) {
                setMessage({ text: e.message, type: 'err' })
              } finally {
                setSaving(false)
              }
            }}
          />
        )}
        {panel === 'registry' && <NodeRegistryPanel engine={engine} />}
        {panel === 'oban' && <ObanPanel engine={engine} />}
        {panel === 'health' && <HealthPanel engine={engine} />}
      </div>

      {/* ── CHAT PANEL ── */}
      <EngineChat panel={panel} />

      {/* ── Toast ── */}
      {message && (
        <div
          className="engine-toast"
          style={{
            background: message.type === 'ok' ? 'var(--color-success)' : 'var(--color-danger)',
          }}
        >
          {message.text}
        </div>
      )}
    </div>
  )
}

// ═══════════════════════════════════════════════════════════
// ── AI CONFIG PANEL ─────────────────────────────────────
// ═══════════════════════════════════════════════════════════

function AIConfigPanel({
  settings, stats, saving, onModelChange, onSaveProviderKey, onRemoveProviderKey,
}: {
  settings: Settings | null
  stats: Stats | null
  saving: boolean
  onModelChange: (m: string) => void
  onSaveProviderKey: (provider: string, key: string) => void
  onRemoveProviderKey: (provider: string) => void
}) {
  return (
    <div>
      <div className="engine-page-head">
        <h2>AI Configuration</h2>
        <p>პროვაიდერების დაკავშირება და აქტიური მოდელის არჩევა</p>
      </div>

      {/* Stats */}
      {stats && (
        <div className="engine-grid-4" style={{ marginBottom: 18 }}>
          <StatCard icon="💬" value={stats.conversations.total} label="საუბრები" sub={`${stats.conversations.active} აქტიური`} />
          <StatCard icon="📨" value={stats.messages.total} label="შეტყობინებები" />
          <StatCard icon="🔀" value={stats.flows.total} label="ფლოუები" sub={`${stats.flows.active} აქტიური`} />
          <StatCard icon="🧠" value={stats.memories.total} label="მეხსიერება" />
        </div>
      )}

      {/* Provider cards — square tiles */}
      {settings && (
        <Section title="პროვაიდერები" action={null}>
          <div className="engine-provider-grid">
            {settings.available_models.map(provider => (
              <ProviderCard
                key={provider.provider}
                provider={provider}
                currentModel={settings.ai_model}
                hasKey={settings.provider_keys[provider.provider] ?? false}
                isActiveProvider={settings.ai_provider === provider.provider}
                saving={saving}
                onModelChange={onModelChange}
                onSaveKey={(key) => onSaveProviderKey(provider.provider, key)}
                onRemoveKey={() => onRemoveProviderKey(provider.provider)}
              />
            ))}
          </div>
        </Section>
      )}
    </div>
  )
}

/** Square provider tile — click opens modal */
function ProviderCard({
  provider, currentModel, hasKey, isActiveProvider, saving,
  onModelChange, onSaveKey, onRemoveKey,
}: {
  provider: { provider: string; display_name: string; models: { id: string; name: string }[] }
  currentModel: string
  hasKey: boolean
  isActiveProvider: boolean
  saving: boolean
  onModelChange: (m: string) => void
  onSaveKey: (key: string) => void
  onRemoveKey: () => void
}) {
  const [open, setOpen] = useState(false)
  const activeModel = provider.models.find(m => m.id === currentModel)

  return (
    <>
      <button
        className={`engine-pcard ${isActiveProvider ? 'engine-pcard-active' : ''} ${hasKey ? '' : 'engine-pcard-dim'}`}
        onClick={() => setOpen(true)}
      >
        <span className="engine-pcard-icon"><ProviderLogo provider={provider.provider} size={28} /></span>
        <span className="engine-pcard-name">{provider.display_name}</span>
        {hasKey ? <Tag color="green">Connected</Tag> : <Tag color="muted">No key</Tag>}
        {activeModel && (
          <span className="engine-pcard-model">{activeModel.name}</span>
        )}
        {isActiveProvider && <span className="engine-pcard-active-dot" />}
      </button>

      {open && (
        <ProviderModal
          provider={provider}
          currentModel={currentModel}
          hasKey={hasKey}
          isActiveProvider={isActiveProvider}
          saving={saving}
          onModelChange={onModelChange}
          onSaveKey={onSaveKey}
          onRemoveKey={onRemoveKey}
          onClose={() => setOpen(false)}
        />
      )}
    </>
  )
}

/** Modal for configuring a single provider */
function ProviderModal({
  provider, currentModel, hasKey, isActiveProvider, saving,
  onModelChange, onSaveKey, onRemoveKey, onClose,
}: {
  provider: { provider: string; display_name: string; models: { id: string; name: string }[] }
  currentModel: string
  hasKey: boolean
  isActiveProvider: boolean
  saving: boolean
  onModelChange: (m: string) => void
  onSaveKey: (key: string) => void
  onRemoveKey: () => void
  onClose: () => void
}) {
  const [keyInput, setKeyInput] = useState('')
  const [selectedModel, setSelectedModel] = useState(
    provider.models.some(m => m.id === currentModel) ? currentModel : ''
  )

  const handleSaveKey = () => {
    if (keyInput.trim()) {
      onSaveKey(keyInput.trim())
      setKeyInput('')
    }
  }

  const handleActivate = () => {
    if (selectedModel && selectedModel !== currentModel) {
      onModelChange(selectedModel)
    }
    onClose()
  }

  return (
    <div className="engine-modal-backdrop" onClick={onClose}>
      <div className="engine-modal" onClick={e => e.stopPropagation()}>
        {/* Header */}
        <div className="engine-modal-head">
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <ProviderLogo provider={provider.provider} size={24} />
            <div>
              <div className="engine-modal-title">{provider.display_name}</div>
              <div className="engine-modal-sub">
                {hasKey ? 'დაკავშირებული' : 'არაა დაკავშირებული'}
                {isActiveProvider && ' · აქტიური პროვაიდერი'}
              </div>
            </div>
          </div>
          <button className="engine-modal-close" onClick={onClose}>✕</button>
        </div>

        {/* API Key section */}
        <div className="engine-modal-section">
          <div className="engine-modal-label">API Key</div>
          {hasKey && !keyInput && (
            <div className="engine-modal-key-display">
              <span className="engine-key-dots">{'••••••••••••••••••••'}</span>
              <button
                onClick={onRemoveKey}
                className="engine-provider-remove"
              >
                წაშლა
              </button>
            </div>
          )}
          <div className="engine-provider-key-row">
            <input
              type="password"
              placeholder={keyPlaceholder(provider.provider)}
              value={keyInput}
              onChange={e => setKeyInput(e.target.value)}
              className="engine-input"
              style={{ flex: 1 }}
              onKeyDown={e => { if (e.key === 'Enter') handleSaveKey() }}
            />
            <button
              onClick={handleSaveKey}
              disabled={saving || !keyInput.trim()}
              className="engine-section-action"
              style={{ opacity: saving || !keyInput.trim() ? 0.4 : 1 }}
            >
              {hasKey ? 'განახლება' : 'დაკავშირება'}
            </button>
          </div>
        </div>

        {/* Model selection */}
        <div className="engine-modal-section">
          <div className="engine-modal-label">მოდელი</div>
          <div className="engine-model-chips">
            {provider.models.map(m => (
              <button
                key={m.id}
                className={`engine-model-chip ${m.id === selectedModel ? 'engine-model-chip-selected' : ''}`}
                onClick={() => setSelectedModel(m.id)}
              >
                {m.id === selectedModel && <span className="engine-model-dot" />}
                {m.name}
              </button>
            ))}
          </div>
        </div>

        {/* Footer */}
        <div className="engine-modal-footer">
          <button className="engine-modal-cancel" onClick={onClose}>გაუქმება</button>
          <button
            className="engine-modal-activate"
            onClick={handleActivate}
            disabled={saving || !selectedModel || (!hasKey && !keyInput.trim())}
          >
            {isActiveProvider && selectedModel === currentModel ? 'დახურვა' : 'გააქტიურება'}
          </button>
        </div>
      </div>
      {/* API Key Management */}
      <ApiKeySection />
    </div>
  )
}

// ── API Key Section ──────────────────────────────────────

function ApiKeySection() {
  const [newKey, setNewKey] = useState<string | null>(null)
  const [regenerating, setRegenerating] = useState(false)
  const [copied, setCopied] = useState(false)

  const handleRegenerate = async () => {
    if (!confirm('ახალი API key-ის გენერაცია ძველს გააუქმებს. გავაგრძელოთ?')) return
    setRegenerating(true)
    try {
      const result = await regenerateApiKey()
      setNewKey(result.api_key)
    } catch (e: any) {
      alert('შეცდომა: ' + e.message)
    } finally {
      setRegenerating(false)
    }
  }

  const handleCopy = () => {
    if (newKey) {
      navigator.clipboard.writeText(newKey)
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    }
  }

  return (
    <Section title="🔑 API Key" action={null}>
      <div style={{ padding: '12px 16px' }}>
        <p style={{ fontSize: 11, color: 'var(--color-text-muted)', marginBottom: 12 }}>
          API key გამოიყენება ავტორიზაციისთვის: <code style={{ fontSize: 10 }}>Authorization: Bearer kal_...</code>
        </p>

        {newKey && (
          <div
            style={{
              padding: '10px 14px',
              background: 'var(--color-success-soft)',
              border: '1px solid var(--color-success)',
              borderRadius: 8,
              marginBottom: 12,
              fontSize: 11,
            }}
          >
            <div style={{ fontWeight: 600, marginBottom: 4, color: 'var(--color-success)' }}>
              ახალი API Key (შეინახეთ ახლავე!)
            </div>
            <div style={{ fontFamily: 'var(--font-mono)', fontSize: 10, wordBreak: 'break-all' }}>
              {newKey}
            </div>
            <button
              onClick={handleCopy}
              style={{
                marginTop: 6,
                padding: '3px 10px',
                borderRadius: 4,
                border: '1px solid var(--color-success)',
                background: copied ? 'var(--color-success)' : 'transparent',
                color: copied ? 'white' : 'var(--color-success)',
                fontSize: 10,
                fontFamily: 'inherit',
                cursor: 'pointer',
              }}
            >
              {copied ? '✓ დაკოპირდა' : '📋 კოპირება'}
            </button>
          </div>
        )}

        <button
          onClick={handleRegenerate}
          disabled={regenerating}
          style={{
            padding: '7px 14px',
            borderRadius: 6,
            border: '1px solid var(--color-danger)',
            background: 'var(--color-danger-soft)',
            color: 'var(--color-danger)',
            fontSize: 11,
            fontFamily: 'inherit',
            fontWeight: 500,
            cursor: 'pointer',
          }}
        >
          {regenerating ? '...' : '🔄 ახალი Key-ის გენერაცია'}
        </button>
      </div>
    </Section>
  )
}

// ═══════════════════════════════════════════════════════════
// ── NODE REGISTRY PANEL ─────────────────────────────────
// ═══════════════════════════════════════════════════════════

function NodeRegistryPanel({ engine }: { engine: EngineData | null }) {
  if (!engine) return <Loading />

  const { node_registry } = engine
  const grouped = groupBy(node_registry.nodes, n => n.category)
  const categoryOrder = ['trigger', 'condition', 'wait', 'action', 'end']

  return (
    <div>
      <div className="engine-page-head">
        <h2>Node Registry</h2>
        <p>{node_registry.total} registered nodes across {Object.keys(node_registry.categories).length} categories — ETS-backed registry mapping string type → module</p>
      </div>

      <div className="engine-grid-4" style={{ marginBottom: 18 }}>
        <StatCard icon="⚙" value={node_registry.total} label="Registered" />
        <StatCard icon="🎯" value={Object.keys(node_registry.categories).length} label="Categories" />
        <StatCard icon="✅" value={node_registry.total} label="Healthy" />
        <StatCard icon="📌" value={0} label="Errors" />
      </div>

      {categoryOrder.map(cat => {
        const nodes = grouped[cat]
        if (!nodes || nodes.length === 0) return null
        return (
          <Section key={cat} title={`${capitalize(cat)} Nodes (${nodes.length})`} action={null}>
            <div className="engine-card" style={{ padding: 0, overflow: 'hidden' }}>
              <table className="engine-table">
                <thead>
                  <tr>
                    <th>Type Key</th>
                    <th>Module</th>
                    <th>Category</th>
                    <th>Status</th>
                  </tr>
                </thead>
                <tbody>
                  {nodes.map(node => (
                    <tr key={node.type}>
                      <td style={{ fontWeight: 500 }}><code>{node.type}</code></td>
                      <td style={{ fontFamily: 'var(--font-mono)', fontSize: 10 }}>{node.module}</td>
                      <td><Tag color={categoryTagColor(node.category)}>{node.category}</Tag></td>
                      <td><Tag color="green">● registered</Tag></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </Section>
        )
      })}

      <Section title="NodeBehaviour Callbacks" action={null}>
        <div style={{ fontSize: 11, color: 'var(--color-text-sec)', lineHeight: 1.8, fontFamily: 'var(--font-mono)' }}>
          <code>execute/2</code> → <code>{'{:completed, result}'}</code> | <code>{'{:branched, branch_key, result}'}</code> | <code>{'{:waiting, wait_config}'}</code> | <code>{'{:failed, reason}'}</code><br />
          <code>resume/3</code> — optional, for wait nodes<br />
          <code>validate/1</code> — optional, config validation<br />
          <code>config_schema/0</code> — returns JSON schema for node config<br />
          <code>category/0</code> — <code>:trigger | :condition | :wait | :action | :end</code>
        </div>
      </Section>
    </div>
  )
}

// ═══════════════════════════════════════════════════════════
// ── OBAN QUEUES PANEL ───────────────────────────────────
// ═══════════════════════════════════════════════════════════

function ObanPanel({ engine }: { engine: EngineData | null }) {
  if (!engine) return <Loading />
  const { oban } = engine

  return (
    <div>
      <div className="engine-page-head">
        <h2>Oban Queues</h2>
        <p>Oban job queue configuration — {oban.queues.length} queues with configurable concurrency</p>
      </div>

      <div className="engine-grid-3" style={{ marginBottom: 18 }}>
        <StatCard icon="" value={oban.total_concurrency} label="Total Concurrency" color="var(--color-success)" />
        <StatCard icon="" value={oban.total_completed_24h} label="Jobs (24h)" color="var(--color-info)" />
        <StatCard icon="" value={oban.total_failed_24h} label="Failed (24h)" color={oban.total_failed_24h > 0 ? 'var(--color-danger)' : 'var(--color-success)'} />
      </div>

      <div className="engine-grid-3">
        {oban.queues.map(q => (
          <div key={q.name} className="engine-card engine-infra-card">
            <div className="engine-infra-head">
              <div className="engine-infra-title">
                <span>{queueIcon(q.name)}</span> {q.name}
              </div>
              <div className="engine-infra-status">
                <div className="engine-status-dot" style={{ background: 'var(--color-success)' }} />
                <span style={{ color: 'var(--color-success)' }}>Running</span>
              </div>
            </div>
            <div className="engine-infra-metrics">
              <InfraMetric label="Concurrency" value={String(q.concurrency)} />
              <InfraMetric label="Executing" value={String(q.executing)} bar={q.concurrency > 0 ? (q.executing / q.concurrency) * 100 : 0} />
              <InfraMetric label="Completed (24h)" value={formatNum(q.completed_24h)} />
              <InfraMetric label="Available" value={String(q.available)} />
              <InfraMetric label="Failed (24h)" value={String(q.failed_24h)} valueColor={q.failed_24h > 0 ? 'var(--color-danger)' : 'var(--color-success)'} />
              <InfraMetric label="Scheduled" value={String(q.scheduled)} />
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}

// ═══════════════════════════════════════════════════════════
// ── SYSTEM HEALTH PANEL ─────────────────────────────────
// ═══════════════════════════════════════════════════════════

function HealthPanel({ engine }: { engine: EngineData | null }) {
  if (!engine) return <Loading />
  const { vm, db, instances, oban, node_registry } = engine

  const uptimeStr = formatUptime(vm.uptime_seconds)
  const memPercent = vm.memory_total_mb > 0 ? Math.min(100, (vm.memory_total_mb / 512) * 100) : 0

  return (
    <div>
      <div className="engine-page-head">
        <h2>System Health</h2>
        <p>Overall engine health — Elixir/OTP, PostgreSQL, Oban, process counts, memory</p>
      </div>

      <div className="engine-grid-4" style={{ marginBottom: 18 }}>
        <StatCard icon="⚡" value={`${db.latency_ms}ms`} label="DB Latency" />
        <StatCard icon="📊" value={formatNum(vm.process_count)} label="BEAM Processes" />
        <StatCard icon="🔀" value={instances.total_active} label="Active Instances" sub={`${instances.running} running, ${instances.waiting} waiting`} />
        <StatCard icon="⏱" value={uptimeStr} label="Uptime" />
      </div>

      {/* Service Status Alerts */}
      <Section title="Service Status" action={null}>
        <div className="engine-grid-2">
          <AlertRow ok title={`Elixir ${vm.elixir_version} / OTP ${vm.otp_release}`} desc={`Schedulers: ${vm.schedulers} · Memory: ${vm.memory_total_mb}MB · Run Queue: ${vm.run_queue}`} />
          <AlertRow ok title={`${db.adapter}`} desc={`Pool: ${db.pool_size} · Latency: ${db.latency_ms}ms`} />
          <AlertRow ok title="Oban" desc={`${oban.queues.length} queues · ${oban.total_concurrency} concurrency · ${oban.total_failed_24h} failed`} />
          <AlertRow ok title="Node Registry (ETS)" desc={`${node_registry.total} nodes registered · All callbacks validated`} />
          <AlertRow ok title="Engine Supervisor" desc={`rest_for_one strategy · ${instances.total_active} active FlowServers`} />
          <AlertRow ok={instances.running >= 0} title="Flow Instances" desc={`${instances.running} running · ${instances.waiting} waiting`} />
        </div>
      </Section>

      {/* VM + DB detail cards */}
      <div className="engine-grid-2">
        <div className="engine-card engine-infra-card">
          <div className="engine-infra-head">
            <div className="engine-infra-title"><span>⚡</span> BEAM VM</div>
            <div className="engine-infra-status">
              <div className="engine-status-dot" style={{ background: 'var(--color-success)' }} />
              <span style={{ color: 'var(--color-success)' }}>Healthy</span>
            </div>
          </div>
          <div className="engine-infra-metrics">
            <InfraMetric label="Processes" value={formatNum(vm.process_count)} />
            <InfraMetric label="Memory" value={`${vm.memory_total_mb}MB`} bar={memPercent} />
            <InfraMetric label="Schedulers" value={String(vm.schedulers)} />
            <InfraMetric label="Run Queue" value={String(vm.run_queue)} />
            <InfraMetric label="ETS Memory" value={`${vm.memory_ets_mb}MB`} />
            <InfraMetric label="Uptime" value={uptimeStr} />
          </div>
        </div>

        <div className="engine-card engine-infra-card">
          <div className="engine-infra-head">
            <div className="engine-infra-title"><span>🐘</span> PostgreSQL</div>
            <div className="engine-infra-status">
              <div className="engine-status-dot" style={{ background: 'var(--color-success)' }} />
              <span style={{ color: 'var(--color-success)' }}>Healthy</span>
            </div>
          </div>
          <div className="engine-infra-metrics">
            <InfraMetric label="Pool Size" value={String(db.pool_size)} />
            <InfraMetric label="Latency" value={`${db.latency_ms}ms`} />
            <InfraMetric label="Active Instances" value={String(instances.total_active)} />
            <InfraMetric label="Process Mem" value={`${vm.memory_processes_mb}MB`} />
          </div>
        </div>
      </div>

      {/* Recent Logs */}
      <Section title={`Recent Logs (${engine.logs.length})`} action={null}>
        <div className="engine-card" style={{ padding: 0, overflow: 'hidden' }}>
          <div className="engine-log-stream">
            {engine.logs.length === 0 && (
              <div style={{ padding: 16, textAlign: 'center', color: 'var(--color-text-muted)', fontSize: 11 }}>
                ლოგები ჯერ არ არის
              </div>
            )}
            {engine.logs.map((log, i) => (
              <LogRow key={i} log={log} />
            ))}
          </div>
        </div>
      </Section>

      {/* Supervision tree */}
      <Section title="Supervision Tree" action={null}>
        <div style={{ fontFamily: 'var(--font-mono)', fontSize: 10, color: 'var(--color-text-sec)', lineHeight: 2 }}>
          <code>Engine.Supervisor</code> (rest_for_one)<br />
          &nbsp;&nbsp;├ <code>LogCollector</code> (GenServer — ring buffer)<br />
          &nbsp;&nbsp;├ <code>NodeRegistry</code> (ETS — {node_registry.total} nodes)<br />
          &nbsp;&nbsp;├ <code>EventRouter</code> (GenServer)<br />
          &nbsp;&nbsp;├ <code>DynamicSupervisor</code> ({instances.total_active} FlowServers)<br />
          &nbsp;&nbsp;└ <code>RecoveryManager</code> (GenServer)
        </div>
      </Section>
    </div>
  )
}

function LogRow({ log }: { log: LogEntry }) {
  const time = new Date(log.timestamp).toLocaleTimeString('ka-GE', { hour12: false })
  const levelColor: Record<string, string> = {
    debug: 'var(--color-text-muted)',
    info: 'var(--color-info)',
    warning: 'var(--color-warn)',
    error: 'var(--color-danger)',
  }
  const color = levelColor[log.level] ?? 'var(--color-text-sec)'

  return (
    <div className="engine-log-row">
      <span className="engine-log-time">{time}</span>
      <span className="engine-log-level" style={{ color }}>{log.level.toUpperCase()}</span>
      {log.module && <span className="engine-log-module">{log.module.replace('Elixir.', '')}</span>}
      <span className="engine-log-msg">{log.message}</span>
    </div>
  )
}

// ═══════════════════════════════════════════════════════════
// ── SHARED UI COMPONENTS ────────────────────────────────
// ═══════════════════════════════════════════════════════════

function Loading() {
  return (
    <div style={{ padding: 40, textAlign: 'center', color: 'var(--color-text-muted)', fontSize: 13 }}>
      იტვირთება...
    </div>
  )
}

function Section({ title, action, children }: { title: string; action: string | null; children: React.ReactNode }) {
  return (
    <div className="engine-section">
      <div className="engine-section-head">
        <div className="engine-section-title">{title}</div>
        {action && <button className="engine-section-action">{action}</button>}
      </div>
      {children}
    </div>
  )
}

function StatCard({ icon, value, label, sub, color }: { icon: string; value: string | number; label: string; sub?: string; color?: string }) {
  return (
    <div className="engine-card engine-stat">
      {icon && <div className="engine-stat-icon">{icon}</div>}
      <div className="engine-stat-value" style={color ? { color } : undefined}>{typeof value === 'number' ? formatNum(value) : value}</div>
      <div className="engine-stat-label">{label}</div>
      {sub && <div className="engine-stat-sub">{sub}</div>}
    </div>
  )
}

function Tag({ color, children }: { color: string; children: React.ReactNode }) {
  const colorMap: Record<string, { bg: string; fg: string }> = {
    green: { bg: 'var(--color-success-soft)', fg: 'var(--color-success)' },
    orange: { bg: 'var(--color-warn-soft)', fg: 'var(--color-warn)' },
    red: { bg: 'var(--color-danger-soft)', fg: 'var(--color-danger)' },
    blue: { bg: 'var(--color-info-soft)', fg: 'var(--color-info)' },
    muted: { bg: 'var(--color-accent-soft)', fg: 'var(--color-text-muted)' },
  }
  const c = colorMap[color] ?? colorMap.muted!
  return (
    <span className="engine-tag" style={{ background: c.bg, color: c.fg }}>
      {children}
    </span>
  )
}

function InfraMetric({ label, value, bar, valueColor }: { label: string; value: string; bar?: number; valueColor?: string }) {
  return (
    <div className="engine-infra-metric">
      <div className="engine-im-label">{label}</div>
      <div className="engine-im-value" style={valueColor ? { color: valueColor } : undefined}>{value}</div>
      {bar !== undefined && (
        <div className="engine-im-bar">
          <div className="engine-im-fill" style={{ width: `${Math.min(100, bar)}%`, background: bar > 80 ? 'var(--color-warn)' : 'var(--color-success)' }} />
        </div>
      )}
    </div>
  )
}

function AlertRow({ ok, title, desc }: { ok: boolean; title: string; desc: string }) {
  return (
    <div className={`engine-alert ${ok ? 'engine-alert-ok' : 'engine-alert-warn'}`}>
      <div className="engine-alert-icon">{ok ? '✅' : '⚠️'}</div>
      <div className="engine-alert-content">
        <div className="engine-alert-title">{title}</div>
        <div className="engine-alert-desc">{desc}</div>
      </div>
    </div>
  )
}

// ═══════════════════════════════════════════════════════════
// ── ENGINE CHAT PANEL ───────────────────────────────────
// ═══════════════════════════════════════════════════════════

const PANEL_HINTS: Record<string, string> = {
  ai: 'AI Configuration — აქ ირჩევ რომელ პროვაიდერს და მოდელს იყენებს კალციფერი. დააკავშირე პროვაიდერი API key-ით და აირჩიე მოდელი.',
  registry: 'Node Registry — ყველა რეგისტრირებული node type, ETS-ში. თითოეულს აქვს execute/2 callback და category (trigger, condition, wait, action, end).',
  oban: 'Oban Queues — background job system. flow_triggers ეშვება ახალი ფლოუ ტრიგერებისთვის, delayed_resume wait node-ების გასაგრძელებლად, maintenance cleanup-ისთვის.',
  health: 'System Health — BEAM VM, PostgreSQL, და engine supervisor-ის სტატუსი. აქ ხედავ memory-ს, process count-ს, DB latency-ს.',
}

function EngineChat({ panel }: { panel: PanelId }) {
  const [collapsed, setCollapsed] = useState(false)

  if (collapsed) {
    return (
      <div
        style={{
          width: 32, borderLeft: '1px solid var(--color-border)',
          display: 'flex', alignItems: 'flex-start', justifyContent: 'center',
          paddingTop: 12, cursor: 'pointer', background: 'var(--color-bg)',
        }}
        onClick={() => setCollapsed(false)}
        title="Call Kalcifer"
      >
        <span style={{ fontSize: 14, color: 'var(--color-text-muted)', writingMode: 'vertical-rl' }}>Kalcifer</span>
      </div>
    )
  }

  return (
    <div className="engine-chat">
      {/* Header */}
      <div className="engine-chat-head">
        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          <div className="engine-health-dot" style={{ width: 6, height: 6 }} />
          <span style={{ fontSize: 12, fontWeight: 600, color: 'var(--color-text)' }}>Kalcifer</span>
        </div>
        <button
          onClick={() => setCollapsed(true)}
          style={{
            background: 'none', border: 'none', color: 'var(--color-text-muted)',
            cursor: 'pointer', fontSize: 14, padding: '2px 4px', borderRadius: 'var(--radius-xs)',
          }}
        >
          →
        </button>
      </div>

      {/* Messages */}
      <div className="engine-chat-msgs">
        <div className="engine-chat-msg-ai">
          <div className="engine-chat-avatar">K</div>
          <div className="engine-chat-bubble">
            {PANEL_HINTS[panel]}
          </div>
        </div>
      </div>

      {/* Input */}
      <div className="engine-chat-input-area">
        <div className="engine-chat-input-wrap">
          <input
            type="text"
            placeholder="Ask about engine configuration..."
            className="engine-chat-input"
            onKeyDown={() => {}}
          />
          <button className="engine-chat-send">
            <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
              <path d="M22 2L11 13M22 2l-7 20-4-9-9-4 20-7z" />
            </svg>
          </button>
        </div>
      </div>
    </div>
  )
}

// ── Helpers ──────────────────────────────────────────────

function groupBy<T>(arr: T[], fn: (item: T) => string): Record<string, T[]> {
  return arr.reduce((acc, item) => {
    const key = fn(item)
    ;(acc[key] = acc[key] || []).push(item)
    return acc
  }, {} as Record<string, T[]>)
}

function capitalize(s: string) {
  return s.charAt(0).toUpperCase() + s.slice(1)
}

function formatNum(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`
  if (n >= 10_000) return `${(n / 1000).toFixed(1)}K`
  return n.toLocaleString()
}

function formatUptime(seconds: number): string {
  const days = Math.floor(seconds / 86_400)
  const hours = Math.floor((seconds % 86_400) / 3600)
  const mins = Math.floor((seconds % 3600) / 60)
  if (days > 0) return `${days}d ${hours}h`
  if (hours > 0) return `${hours}h ${mins}m`
  return `${mins}m`
}

function categoryTagColor(cat: string): string {
  switch (cat) {
    case 'trigger': return 'blue'
    case 'condition': return 'orange'
    case 'wait': return 'muted'
    case 'action': return 'green'
    case 'end': return 'red'
    default: return 'muted'
  }
}

function keyPlaceholder(provider: string): string {
  switch (provider) {
    case 'anthropic': return 'sk-ant-api03-...'
    case 'openai': return 'sk-proj-...'
    case 'google': return 'AIzaSy...'
    default: return 'API key...'
  }
}

function ProviderLogo({ provider, size = 22 }: { provider: string; size?: number }) {
  switch (provider) {
    case 'anthropic':
      // Claude — sparkle/sunburst icon
      return (
        <svg width={size} height={size} viewBox="0 0 24 24" fill="none">
          <path d="M12 2L13.09 8.26L18 4.93L14.68 9.83L21 10.91L14.68 12L18 16.07L13.09 13.74L12 20L10.91 13.74L6 16.07L9.32 12L3 10.91L9.32 9.83L6 4.93L10.91 8.26L12 2Z" fill="#D4A27F" />
        </svg>
      )
    case 'openai':
      // ChatGPT — simplified chat bubble
      return (
        <svg width={size} height={size} viewBox="0 0 24 24" fill="none">
          <path d="M22.282 9.821a5.985 5.985 0 00-.516-4.91 6.046 6.046 0 00-6.51-2.9A6.065 6.065 0 0011.702.013a6.04 6.04 0 00-5.78 4.214 6.04 6.04 0 00-4.029 2.929 6.05 6.05 0 00.749 7.11 5.98 5.98 0 00.516 4.911 6.05 6.05 0 006.51 2.9A6.06 6.06 0 0013.22 23.99a6.04 6.04 0 005.78-4.215 6.04 6.04 0 004.029-2.928 6.05 6.05 0 00-.748-7.026zM13.22 22.43a4.476 4.476 0 01-2.876-1.04l.143-.08 4.778-2.758a.776.776 0 00.392-.681v-6.737l2.02 1.166a.071.071 0 01.038.052v5.583a4.504 4.504 0 01-4.494 4.494zM3.197 18.267a4.49 4.49 0 01-.535-3.014l.143.086 4.778 2.758a.773.773 0 00.782 0l5.832-3.369v2.332a.074.074 0 01-.028.06L9.338 19.9a4.504 4.504 0 01-6.14-1.634zM2.046 7.937a4.49 4.49 0 012.34-1.975l-.002.164v5.517a.774.774 0 00.39.68l5.833 3.369-2.02 1.166a.073.073 0 01-.067.006L3.69 14.087a4.504 4.504 0 01-1.645-6.15zm16.588 3.862l-5.833-3.387 2.02-1.164a.074.074 0 01.068-.006l4.83 2.788a4.494 4.494 0 01-.692 8.112v-5.68a.79.79 0 00-.393-.663zm2.01-3.024l-.144-.085-4.777-2.76a.773.773 0 00-.782 0L9.108 9.3V6.968a.074.074 0 01.028-.06l4.83-2.787a4.495 4.495 0 016.678 4.653zM8.076 12.5l-2.02-1.166a.072.072 0 01-.038-.053V5.698a4.495 4.495 0 017.375-3.453l-.143.08-4.778 2.758a.776.776 0 00-.392.68zm1.097-2.368L12 8.59l2.828 1.542v3.084L12 14.757l-2.828-1.541z" fill="#10A37F" />
        </svg>
      )
    case 'google':
      // Gemini — 4-point star
      return (
        <svg width={size} height={size} viewBox="0 0 24 24" fill="none">
          <path d="M12 2C12 2 14.5 9.5 14.5 12C14.5 14.5 12 22 12 22C12 22 9.5 14.5 9.5 12C9.5 9.5 12 2 12 2Z" fill="#4285F4" />
          <path d="M2 12C2 12 9.5 9.5 12 9.5C14.5 9.5 22 12 22 12C22 12 14.5 14.5 12 14.5C9.5 14.5 2 12 2 12Z" fill="#4285F4" />
        </svg>
      )
    default:
      return <span style={{ fontSize: size, lineHeight: 1 }}>⚪</span>
  }
}

// ── Channels Panel ──────────────────────────────────────

const CHANNEL_ICONS: Record<string, string> = {
  email: '📧',
  sms: '💬',
  push: '🔔',
  whatsapp: '💚',
  webhook: '🔗',
}

const AVAILABLE_PROVIDERS: Record<string, string[]> = {
  email: ['log', 'sendgrid', 'ses', 'mailgun', 'postmark'],
  sms: ['log', 'twilio', 'vonage', 'messagebird'],
  push: ['log', 'firebase', 'onesignal', 'expo'],
  whatsapp: ['log', 'twilio', 'messagebird'],
  webhook: ['log', 'webhook'],
}

function ChannelsPanel({
  providers,
  saving,
  onUpdate,
}: {
  providers: { channel: string; provider: string; enabled: boolean; configured: boolean }[]
  saving: boolean
  onUpdate: (channel: string, provider: string) => void
}) {
  return (
    <div style={{ padding: 20 }}>
      <h2 style={{ fontSize: 16, fontWeight: 600, marginBottom: 16, color: 'var(--color-text)' }}>
        📡 Channel Providers
      </h2>
      <p style={{ fontSize: 12, color: 'var(--color-text-muted)', marginBottom: 16 }}>
        თითოეული არხისთვის აირჩიეთ პროვაიდერი. &quot;log&quot; სატესტოა — ყველაფერს კონსოლში წერს.
      </p>
      <div style={{ display: 'grid', gap: 10 }}>
        {providers.map(p => (
          <div
            key={p.channel}
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: 12,
              padding: '12px 16px',
              background: 'var(--color-surface)',
              border: '1px solid var(--color-border)',
              borderRadius: 10,
            }}
          >
            <span style={{ fontSize: 20 }}>{CHANNEL_ICONS[p.channel] || '📡'}</span>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 13, fontWeight: 600, color: 'var(--color-text)' }}>
                {p.channel}
              </div>
              <div style={{ fontSize: 10, color: 'var(--color-text-muted)' }}>
                {p.configured ? 'კონფიგურირებული' : 'ლოგ-რეჟიმი (ტესტი)'}
              </div>
            </div>
            <select
              value={p.provider}
              onChange={e => onUpdate(p.channel, e.target.value)}
              disabled={saving}
              style={{
                padding: '5px 10px',
                borderRadius: 6,
                border: '1px solid var(--color-border)',
                background: 'var(--color-surface-dim)',
                color: 'var(--color-text)',
                fontSize: 11,
                fontFamily: 'inherit',
                cursor: 'pointer',
              }}
            >
              {(AVAILABLE_PROVIDERS[p.channel] || ['log']).map(prov => (
                <option key={prov} value={prov}>{prov}</option>
              ))}
            </select>
            <span
              style={{
                width: 8,
                height: 8,
                borderRadius: '50%',
                background: p.configured ? 'var(--color-success)' : 'var(--color-text-muted)',
              }}
              title={p.configured ? 'Active' : 'Log mode'}
            />
          </div>
        ))}
      </div>
    </div>
  )
}

function queueIcon(name: string): string {
  switch (name) {
    case 'flow_triggers': return '🔥'
    case 'delayed_resume': return '⏰'
    case 'maintenance': return '🔧'
    default: return '📋'
  }
}
