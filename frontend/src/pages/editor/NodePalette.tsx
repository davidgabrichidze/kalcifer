import { NODE_TYPES, type NodeCategory } from './nodeTypes'
import './editor.css'

interface NodePaletteProps {
  isOpen: boolean
  onClose: () => void
  onAddNode: (nodeType: string) => void
}

const categories: NodeCategory[] = ['trigger', 'condition', 'wait', 'action', 'end']

const categoryLabels: Record<NodeCategory, string> = {
  trigger: 'Trigger',
  condition: 'Condition',
  wait: 'Wait',
  action: 'Action',
  end: 'End',
}

const actionSubcategories: Record<string, string> = {
  send_email: 'Channel',
  send_sms: 'Channel',
  send_push: 'Channel',
  send_whatsapp: 'Channel',
  send_in_app: 'Channel',
  call_webhook: 'Data',
  track_conversion: 'Data',
  add_tag: 'Data',
  update_profile: 'Data',
}

export function NodePalette({ isOpen, onClose, onAddNode }: NodePaletteProps) {
  const categoryColorMap: Record<NodeCategory, { bg: string; text: string; border: string }> = {
    trigger: {
      bg: 'var(--color-info-soft)',
      text: 'var(--color-info)',
      border: 'rgba(106, 143, 160, 0.2)',
    },
    action: {
      bg: 'var(--color-primary-soft)',
      text: 'var(--color-primary)',
      border: 'rgba(192, 122, 62, 0.2)',
    },
    condition: {
      bg: 'var(--color-warn-soft)',
      text: 'var(--color-warn)',
      border: 'rgba(196, 154, 74, 0.2)',
    },
    wait: {
      bg: 'var(--color-accent-soft)',
      text: 'var(--color-accent)',
      border: 'rgba(139, 109, 74, 0.2)',
    },
    end: {
      bg: 'var(--color-success-soft)',
      text: 'var(--color-success)',
      border: 'rgba(90, 158, 111, 0.2)',
    },
  }

  const renderCategory = (category: NodeCategory) => {
    const nodes = Object.values(NODE_TYPES).filter(nt => nt.category === category)

    if (category === 'action') {
      // Split action nodes into subcategories
      const channelNodes = nodes.filter(nt => actionSubcategories[nt.key] === 'Channel')
      const dataNodes = nodes.filter(nt => actionSubcategories[nt.key] === 'Data')

      return (
        <div key={category}>
          {channelNodes.length > 0 && (
            <div className="palette-section">
              <div className="palette-label">Action — Channel</div>
              {channelNodes.map(nodeType => renderNodeItem(nodeType, category, categoryColorMap))}
            </div>
          )}
          {dataNodes.length > 0 && (
            <div className="palette-section">
              <div className="palette-label">Action — Data</div>
              {dataNodes.map(nodeType => renderNodeItem(nodeType, category, categoryColorMap))}
            </div>
          )}
        </div>
      )
    }

    return (
      <div key={category} className="palette-section">
        <div className="palette-label">{categoryLabels[category]}</div>
        {nodes.map(nodeType => renderNodeItem(nodeType, category, categoryColorMap))}
      </div>
    )
  }

  const renderNodeItem = (
    nodeType: typeof NODE_TYPES[string],
    category: NodeCategory,
    colorMap: Record<NodeCategory, { bg: string; text: string; border: string }>,
  ) => {
    const colors = colorMap[category]

    return (
      <div
        key={nodeType.key}
        className="palette-node"
        draggable
        onDragStart={e => {
          e.dataTransfer!.effectAllowed = 'move'
          e.dataTransfer!.setData('application/json', JSON.stringify({ type: nodeType.key }))
        }}
        onClick={() => onAddNode(nodeType.key)}
        style={{ cursor: 'grab' }}
      >
        <div
          className="palette-node-icon"
          style={{
            backgroundColor: colors.bg,
            color: colors.text,
            border: `1px solid ${colors.border}`,
          }}
        >
          {nodeType.icon}
        </div>
        <div className="palette-node-info">
          <div className="palette-node-name">{nodeType.label}</div>
          <div className="palette-node-desc">{nodeType.description}</div>
        </div>
      </div>
    )
  }

  return (
    <div className={`palette-panel ${isOpen ? 'open' : ''}`}>
      <div className="palette-header">
        <h3>Node Palette</h3>
        <button
          className="palette-close"
          onClick={onClose}
          aria-label="Close palette"
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
      <div className="palette-body">{categories.map(cat => renderCategory(cat))}</div>
    </div>
  )
}
