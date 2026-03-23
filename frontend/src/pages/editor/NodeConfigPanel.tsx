import { useCallback } from 'react'
import './editor.css'

interface NodeConfigPanelProps {
  isOpen: boolean
  nodeId: string | null
  nodeType: string
  nodeLabel: string
  nodeDescription: string
  nodeConfig: Record<string, unknown>
  onClose: () => void
  onSave: (config: Record<string, unknown>) => void
  onDelete: () => void
}

export function NodeConfigPanel({
  isOpen,
  nodeId,
  nodeType,
  nodeLabel,
  nodeDescription,
  nodeConfig,
  onClose,
  onSave,
  onDelete,
}: NodeConfigPanelProps) {
  const handleLabelChange = useCallback(
    (_e: React.ChangeEvent<HTMLInputElement>) => {
      // This would need parent state management
    },
    [],
  )

  const handleDescriptionChange = useCallback(
    (_e: React.ChangeEvent<HTMLTextAreaElement>) => {
      // This would need parent state management
    },
    [],
  )

  const handleConfigChange = useCallback(
    (key: string, value: unknown) => {
      const newConfig = { ...nodeConfig, [key]: value }
      onSave(newConfig)
    },
    [nodeConfig, onSave],
  )

  const handleRawConfigChange = useCallback(
    (e: React.ChangeEvent<HTMLTextAreaElement>) => {
      try {
        const newConfig = JSON.parse(e.target.value)
        onSave(newConfig)
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
            defaultValue={nodeLabel}
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
            defaultValue={nodeDescription}
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
          <div className="config-field">
            <label className="config-label">Expression</label>
            <input
              className="config-input"
              type="text"
              placeholder="e.g., user.age > 18"
              defaultValue={(nodeConfig.expression as string) || ''}
              onChange={e => handleConfigChange('expression', e.target.value)}
            />
          </div>
        )}

        {nodeType === 'send_email' && (
          <>
            <div className="config-field">
              <label className="config-label">Subject</label>
              <input
                className="config-input"
                type="text"
                placeholder="Email subject"
                defaultValue={(nodeConfig.subject as string) || ''}
                onChange={e => handleConfigChange('subject', e.target.value)}
              />
            </div>
            <div className="config-field">
              <label className="config-label">Template</label>
              <input
                className="config-input"
                type="text"
                placeholder="Template ID or name"
                defaultValue={(nodeConfig.template as string) || ''}
                onChange={e => handleConfigChange('template', e.target.value)}
              />
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
          onClick={() => onSave(nodeConfig)}
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
