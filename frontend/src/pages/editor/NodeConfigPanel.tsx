import { useCallback, useEffect, useState } from 'react'
import { fetchFlows, type Flow } from '../../lib/api'
import { type NodePatch } from '../../components/FlowCanvas'
import './editor.css'

interface NodeConfigPanelProps {
  isOpen: boolean
  nodeId: string | null
  nodeType: string
  nodeLabel: string
  nodeDescription: string
  nodeConfig: Record<string, unknown>
  onClose: () => void
  onSave: (patch: NodePatch) => void
  onDelete: () => void
}

export function NodeConfigPanel({
  isOpen,
  nodeId,
  nodeType,
  nodeLabel: initialLabel,
  nodeDescription: initialDescription,
  nodeConfig: initialConfig,
  onClose,
  onSave,
  onDelete,
}: NodeConfigPanelProps) {
  // Local working copies (shadowing the props) so multi-field edits accumulate
  // correctly. The parent remounts this panel per node (key={nodeId}), so these
  // seed from the freshly selected node.
  const [nodeLabel, setNodeLabel] = useState(initialLabel)
  const [nodeDescription, setNodeDescription] = useState(initialDescription)
  const [nodeConfig, setNodeConfig] = useState<Record<string, unknown>>(initialConfig)

  const handleLabelChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const value = e.target.value
      setNodeLabel(value)
      onSave({ label: value })
    },
    [onSave],
  )

  const handleDescriptionChange = useCallback(
    (e: React.ChangeEvent<HTMLTextAreaElement>) => {
      const value = e.target.value
      setNodeDescription(value)
      onSave({ description: value })
    },
    [onSave],
  )

  const handleConfigChange = useCallback(
    (key: string, value: unknown) => {
      setNodeConfig(prev => {
        const next = { ...prev, [key]: value }
        onSave({ config: next })
        return next
      })
    },
    [onSave],
  )

  const handleRawConfigChange = useCallback(
    (e: React.ChangeEvent<HTMLTextAreaElement>) => {
      try {
        const next = JSON.parse(e.target.value)
        setNodeConfig(next)
        onSave({ config: next })
      } catch {
        // Invalid JSON, don't update
      }
    },
    [onSave],
  )

  if (!nodeId) {
    return null
  }

  return (
    <div className={`config-panel ${isOpen ? 'open' : ''}`}>
      <div className="config-header">
        <h3>Node Config</h3>
        <button
          className="palette-close"
          onClick={onClose}
          aria-label="Close config panel"
          style={{
            background: 'none',
            border: 'none',
            color: 'var(--color-text-muted)',
            cursor: 'pointer',
            fontSize: '16px',
            padding: '2px 6px',
            borderRadius: 'var(--radius-xs)',
            transition: 'all 0.2s',
          }}
          onMouseEnter={e => {
            ;(e.target as HTMLElement).style.color = 'var(--color-text)'
            ;(e.target as HTMLElement).style.background = 'var(--color-surface-dim)'
          }}
          onMouseLeave={e => {
            ;(e.target as HTMLElement).style.color = 'var(--color-text-muted)'
            ;(e.target as HTMLElement).style.background = 'none'
          }}
        >
          ×
        </button>
      </div>

      <div className="config-body">
        {/* Node title (editable) */}
        <div className="config-field">
          <label className="config-label">Title</label>
          <input
            className="config-input"
            type="text"
            value={nodeLabel}
            onChange={handleLabelChange}
            placeholder="Node title"
          />
        </div>

        {/* Node type (disabled) */}
        <div className="config-field">
          <label className="config-label">Type</label>
          <input
            className="config-input"
            type="text"
            value={nodeType}
            disabled
            style={{ opacity: 0.6, cursor: 'not-allowed' }}
          />
        </div>

        {/* Node description */}
        <div className="config-field">
          <label className="config-label">Description</label>
          <textarea
            className="config-textarea"
            value={nodeDescription}
            onChange={handleDescriptionChange}
            placeholder="Node description"
            style={{ minHeight: '60px', fontFamily: 'var(--font-mono)' }}
          />
        </div>

        {/* Type-specific fields */}
        {nodeType === 'wait' && (
          <div className="config-field">
            <label className="config-label">Duration</label>
            <input
              className="config-input"
              type="text"
              placeholder="e.g., 2d, 3h, 30m"
              defaultValue={(nodeConfig.duration as string) || ''}
              onChange={e => handleConfigChange('duration', e.target.value)}
            />
            <div style={{ fontSize: '10px', color: 'var(--color-text-muted)', marginTop: '4px' }}>
              Format: 1d, 2h, 30m, etc.
            </div>
          </div>
        )}

        {nodeType === 'condition' && (
          <>
            <div className="config-field">
              <label className="config-label">Field</label>
              <input
                className="config-input"
                type="text"
                placeholder="მაგ: age, plan, email"
                defaultValue={(nodeConfig.field as string) || ''}
                onChange={e => handleConfigChange('field', e.target.value)}
              />
            </div>
            <div className="config-field">
              <label className="config-label">Operator</label>
              <select
                className="config-select"
                defaultValue={(nodeConfig.operator as string) || 'equals'}
                onChange={e => handleConfigChange('operator', e.target.value)}
              >
                <option value="equals">= ტოლია</option>
                <option value="not_equals">≠ არ არის ტოლი</option>
                <option value="greater_than">&gt; მეტია</option>
                <option value="less_than">&lt; ნაკლებია</option>
                <option value="contains">შეიცავს</option>
                <option value="not_contains">არ შეიცავს</option>
                <option value="exists">არსებობს</option>
                <option value="not_exists">არ არსებობს</option>
                <option value="in">სიაში შედის</option>
                <option value="matches">regex</option>
              </select>
            </div>
            <div className="config-field">
              <label className="config-label">Value</label>
              <input
                className="config-input"
                type="text"
                placeholder="მაგ: premium, 18, @gmail"
                defaultValue={String(nodeConfig.value ?? '')}
                onChange={e => handleConfigChange('value', e.target.value)}
              />
              <div style={{ fontSize: '9px', color: 'var(--color-text-muted)', marginTop: '3px' }}>
                in: მძიმით გამოყოფილი (GE,AM,AZ)
              </div>
            </div>
          </>
        )}

        {nodeType === 'send_email' && (
          <>
            <div className="config-field">
              <label className="config-label">Subject</label>
              <input
                className="config-input"
                type="text"
                placeholder="მაგ: გამარჯობა {{name}}!"
                defaultValue={(nodeConfig.subject as string) || ''}
                onChange={e => handleConfigChange('subject', e.target.value)}
              />
            </div>
            <div className="config-field">
              <label className="config-label">Body</label>
              <textarea
                className="config-textarea"
                placeholder="ემაილის ტექსტი... {{variable}} სინტაქსით ინტერპოლაცია"
                defaultValue={(nodeConfig.body as string) || ''}
                onChange={e => handleConfigChange('body', e.target.value)}
                style={{ minHeight: '120px' }}
              />
              <div style={{ fontSize: '9px', color: 'var(--color-text-muted)', marginTop: '3px' }}>
                {'{{name}}, {{email}}, {{plan}} — context-ის ცვლადები'}
              </div>
            </div>
            <div className="config-field">
              <label className="config-label">From Name</label>
              <input
                className="config-input"
                type="text"
                placeholder="Kalcifer"
                defaultValue={(nodeConfig.from_name as string) || ''}
                onChange={e => handleConfigChange('from_name', e.target.value)}
              />
            </div>
            <div className="config-field">
              <label className="config-label">Reply-To</label>
              <input
                className="config-input"
                type="email"
                placeholder="reply@example.com"
                defaultValue={(nodeConfig.reply_to as string) || ''}
                onChange={e => handleConfigChange('reply_to', e.target.value)}
              />
            </div>
            <div className="config-field">
              <label className="config-label">Template ID (ოპციონალი)</label>
              <input
                className="config-input"
                type="text"
                placeholder="SendGrid template ID"
                defaultValue={(nodeConfig.template_id as string) || ''}
                onChange={e => handleConfigChange('template_id', e.target.value)}
              />
            </div>
          </>
        )}

        {nodeType === 'send_sms' && (
          <>
            <div className="config-field">
              <label className="config-label">SMS ტექსტი</label>
              <textarea
                className="config-textarea"
                placeholder="გამარჯობა {{name}}! თქვენი შეკვეთა მზადაა."
                defaultValue={(nodeConfig.body as string) || ''}
                onChange={e => handleConfigChange('body', e.target.value)}
                style={{ minHeight: '80px' }}
                maxLength={320}
              />
              <div style={{ fontSize: '9px', color: 'var(--color-text-muted)', marginTop: '3px', display: 'flex', justifyContent: 'space-between' }}>
                <span>{'{{name}}, {{phone}} — ცვლადები'}</span>
                <span style={{ color: ((nodeConfig.body as string) || '').length > 160 ? 'var(--color-danger)' : 'var(--color-text-muted)' }}>
                  {((nodeConfig.body as string) || '').length}/160
                </span>
              </div>
            </div>
            <div className="config-field">
              <label className="config-label">Sender ID</label>
              <input
                className="config-input"
                type="text"
                placeholder="Kalcifer"
                defaultValue={(nodeConfig.sender_id as string) || ''}
                onChange={e => handleConfigChange('sender_id', e.target.value)}
              />
            </div>

            {/* Phone mockup preview */}
            <div className="config-field">
              <label className="config-label">Preview</label>
              <div style={{
                width: '100%',
                maxWidth: 220,
                margin: '0 auto',
                background: '#1a1a1a',
                borderRadius: 20,
                padding: '28px 12px 20px',
                position: 'relative',
              }}>
                {/* Notch */}
                <div style={{
                  width: 60,
                  height: 4,
                  background: '#333',
                  borderRadius: 4,
                  margin: '-16px auto 12px',
                }} />
                {/* Screen */}
                <div style={{
                  background: '#f0f0f0',
                  borderRadius: 12,
                  padding: 10,
                  minHeight: 100,
                }}>
                  <div style={{ fontSize: 8, color: '#999', textAlign: 'center', marginBottom: 6 }}>
                    {(nodeConfig.sender_id as string) || 'Kalcifer'}
                  </div>
                  <div style={{
                    background: '#e5e5ea',
                    borderRadius: 12,
                    padding: '8px 10px',
                    fontSize: 10,
                    color: '#000',
                    lineHeight: 1.4,
                    maxWidth: '85%',
                    wordBreak: 'break-word',
                  }}>
                    {(nodeConfig.body as string) || 'შეტყობინების ტექსტი...'}
                  </div>
                </div>
                {/* Home indicator */}
                <div style={{
                  width: 40,
                  height: 3,
                  background: '#555',
                  borderRadius: 3,
                  margin: '10px auto 0',
                }} />
              </div>
            </div>
          </>
        )}

        {nodeType === 'call_webhook' && (
          <>
            <div className="config-field">
              <label className="config-label">URL</label>
              <input
                className="config-input"
                type="text"
                placeholder="https://example.com/webhook"
                defaultValue={(nodeConfig.url as string) || ''}
                onChange={e => handleConfigChange('url', e.target.value)}
              />
            </div>
            <div className="config-field">
              <label className="config-label">Method</label>
              <select
                className="config-input"
                defaultValue={(nodeConfig.method as string) || 'POST'}
                onChange={e => handleConfigChange('method', e.target.value)}
              >
                <option value="POST">POST</option>
                <option value="PUT">PUT</option>
                <option value="PATCH">PATCH</option>
              </select>
            </div>
          </>
        )}

        {nodeType === 'ab_split' && (
          <div className="config-field">
            <label className="config-label">Split Ratio (A %)</label>
            <input
              className="config-input"
              type="number"
              min="0"
              max="100"
              placeholder="50"
              defaultValue={(nodeConfig.splitRatio as number) || 50}
              onChange={e => handleConfigChange('splitRatio', parseInt(e.target.value))}
            />
          </div>
        )}

        {nodeType === 'frequency_cap' && (
          <>
            <div className="config-field">
              <label className="config-label">Max Messages</label>
              <input
                className="config-input"
                type="number"
                min="1"
                placeholder="5"
                defaultValue={(nodeConfig.maxMessages as number) || 5}
                onChange={e => handleConfigChange('maxMessages', parseInt(e.target.value))}
              />
            </div>
            <div className="config-field">
              <label className="config-label">Time Window</label>
              <input
                className="config-input"
                type="text"
                placeholder="e.g., 7d"
                defaultValue={(nodeConfig.timeWindow as string) || ''}
                onChange={e => handleConfigChange('timeWindow', e.target.value)}
              />
            </div>
          </>
        )}

        {nodeType === 'sub_flow' && (
          <SubFlowFields nodeConfig={nodeConfig} onConfigChange={handleConfigChange} />
        )}

        {nodeType === 'parallel_group' && (
          <>
            <div className="config-field">
              <label className="config-label">On Error</label>
              <select
                className="config-input"
                defaultValue={(nodeConfig.on_error as string) || 'continue'}
                onChange={e => handleConfigChange('on_error', e.target.value)}
              >
                <option value="continue">Continue (collect failures)</option>
                <option value="fail_all">Fail all</option>
              </select>
            </div>
            <div className="config-field">
              <label className="config-label">Timeout (ms)</label>
              <input
                className="config-input"
                type="number"
                min="0"
                placeholder="30000"
                defaultValue={(nodeConfig.timeout_ms as number) || ''}
                onChange={e => handleConfigChange('timeout_ms', parseInt(e.target.value))}
              />
            </div>
            <div className="config-hint" style={{ fontSize: '10px', opacity: 0.7 }}>
              Define parallel tasks in the raw config below.
            </div>
          </>
        )}

        {/* Raw JSON config */}
        <div className="config-field">
          <label className="config-label">Raw Config (JSON)</label>
          <textarea
            className="config-textarea"
            value={JSON.stringify(nodeConfig, null, 2)}
            onChange={handleRawConfigChange}
            style={{ minHeight: '80px', fontFamily: 'var(--font-mono)' }}
          />
        </div>
      </div>

      <div className="config-actions">
        <button
          className="config-btn config-btn-p"
          onClick={() => {
            onSave({ label: nodeLabel, description: nodeDescription, config: nodeConfig })
            onClose()
          }}
          style={{
            backgroundColor: 'var(--color-primary)',
            color: 'var(--color-text-on-primary)',
            border: 'none',
            flex: 1,
            padding: '7px',
            borderRadius: 'var(--radius-xs)',
            fontSize: '11px',
            cursor: 'pointer',
            fontWeight: 500,
            transition: 'all 0.2s',
          }}
          onMouseEnter={e => {
            ;(e.target as HTMLElement).style.backgroundColor = 'var(--color-primary-hover)'
          }}
          onMouseLeave={e => {
            ;(e.target as HTMLElement).style.backgroundColor = 'var(--color-primary)'
          }}
        >
          Save
        </button>
        <button
          className="config-btn config-btn-d"
          onClick={onDelete}
          style={{
            backgroundColor: 'var(--color-danger-soft)',
            color: 'var(--color-danger)',
            border: '1px solid transparent',
            flex: 1,
            padding: '7px',
            borderRadius: 'var(--radius-xs)',
            fontSize: '11px',
            cursor: 'pointer',
            fontWeight: 500,
            transition: 'all 0.2s',
          }}
          onMouseEnter={e => {
            ;(e.target as HTMLElement).style.backgroundColor = 'var(--color-danger)'
            ;(e.target as HTMLElement).style.color = 'white'
          }}
          onMouseLeave={e => {
            ;(e.target as HTMLElement).style.backgroundColor = 'var(--color-danger-soft)'
            ;(e.target as HTMLElement).style.color = 'var(--color-danger)'
          }}
        >
          Delete
        </button>
      </div>
    </div>
  )
}

interface SubFlowFieldsProps {
  nodeConfig: Record<string, unknown>
  onConfigChange: (key: string, value: unknown) => void
}

function SubFlowFields({ nodeConfig, onConfigChange }: SubFlowFieldsProps) {
  const [flows, setFlows] = useState<Flow[]>([])
  const [loadError, setLoadError] = useState(false)

  useEffect(() => {
    fetchFlows()
      .then(setFlows)
      .catch(() => setLoadError(true))
  }, [])

  const waitEnabled = nodeConfig.wait === true

  return (
    <>
      <div className="config-field">
        <label className="config-label">Sub-Flow</label>
        {loadError ? (
          <input
            className="config-input"
            type="text"
            placeholder="Flow UUID"
            defaultValue={(nodeConfig.flow_id as string) || ''}
            onChange={e => onConfigChange('flow_id', e.target.value)}
          />
        ) : (
          <select
            className="config-input"
            value={(nodeConfig.flow_id as string) || ''}
            onChange={e => onConfigChange('flow_id', e.target.value)}
          >
            <option value="">Select a flow…</option>
            {flows.map(f => (
              <option key={f.id} value={f.id}>
                {f.name} ({f.status})
              </option>
            ))}
          </select>
        )}
      </div>
      <div className="config-field">
        <label className="config-label" style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
          <input
            type="checkbox"
            checked={waitEnabled}
            onChange={e => onConfigChange('wait', e.target.checked)}
          />
          Wait for sub-flow completion
        </label>
      </div>
      {waitEnabled && (
        <div className="config-field">
          <label className="config-label">Timeout (ms)</label>
          <input
            className="config-input"
            type="number"
            min="0"
            placeholder="60000"
            defaultValue={(nodeConfig.timeout_ms as number) || ''}
            onChange={e => onConfigChange('timeout_ms', parseInt(e.target.value))}
          />
        </div>
      )}
    </>
  )
}
