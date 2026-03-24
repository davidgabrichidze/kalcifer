import { Handle, Position } from '@xyflow/react'
import { getNodeType } from './nodeTypes'
import '../../components/flow-canvas.css'

export interface FlowNodeData {
  label: string
  type: string
  description?: string
  configDetail?: string
}

const categoryColorMap: Record<string, { bg: string; text: string; border: string }> = {
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

export function FlowNode({ data, selected }: { data: FlowNodeData & { simCompleted?: boolean; simActive?: boolean; warnings?: string[] | null }; selected: boolean }) {
  const nodeTypeInfo = getNodeType(data.type)
  const category = nodeTypeInfo?.category || 'action'
  const colors = categoryColorMap[category]

  const isBranching = [
    'condition', 'ab_split', 'frequency_cap', 'check_segment',
    'wait_for_event', 'preference_gate', 'ai_decide',
  ].includes(data.type)

  const simClass = data.simActive ? 'sim-active' : data.simCompleted ? 'sim-completed' : ''

  return (
    <div
      className={`flow-node ${selected ? 'selected' : ''} ${simClass}`}
      style={{
        backgroundColor: 'var(--color-surface)',
        borderColor: data.simActive
          ? 'var(--color-warn)'
          : data.simCompleted
            ? 'var(--color-success)'
            : selected ? 'var(--color-primary)' : 'var(--color-border)',
        boxShadow: data.simActive
          ? '0 0 0 3px var(--color-warn-soft), 0 2px 8px rgba(0,0,0,0.1)'
          : data.simCompleted
            ? '0 0 0 2px var(--color-success-soft)'
            : selected
              ? '0 0 0 3px var(--color-primary-soft), 0 2px 8px rgba(0,0,0,0.06)'
              : '0 2px 8px rgba(0,0,0,0.06)',
      }}
    >
      {/* Input handle (no triggers) */}
      {category !== 'trigger' && (
        <Handle
          type="target"
          position={Position.Top}
          style={{
            backgroundColor: 'var(--color-surface)',
            borderColor: 'var(--color-border)',
          }}
        />
      )}

      {/* Node header with icon and title */}
      <div className="flow-node-header">
        <div
          className="flow-node-icon"
          style={{
            backgroundColor: colors?.bg,
            color: colors?.text,
            border: `1px solid ${colors?.border}`,
          }}
        >
          {nodeTypeInfo?.icon || '○'}
        </div>
        <div className="flow-node-info">
          <div className="flow-node-title">{data.label}</div>
          <div className="flow-node-type">{data.type}</div>
        </div>
        {data.simCompleted && <span className="flow-node-sim-badge completed">✓</span>}
        {data.simActive && <span className="flow-node-sim-badge active">▸</span>}
        {data.warnings && data.warnings.length > 0 && (
          <span
            className="flow-node-warning-badge"
            title={data.warnings.join('\n')}
          >
            ⚠ {data.warnings.length}
          </span>
        )}
      </div>

      {/* Node body */}
      <div className="flow-node-body">
        {data.description && <div className="flow-node-desc">{data.description}</div>}
        {data.configDetail && <div className="flow-node-config">{data.configDetail}</div>}
      </div>

      {/* Output handles */}
      {category !== 'end' && (
        <>
          {isBranching ? (
            <>
              <Handle
                type="source"
                position={Position.Bottom}
                id="true"
                style={{
                  left: '30%',
                  backgroundColor: 'var(--color-success)',
                  borderColor: 'var(--color-surface)',
                  width: 12,
                  height: 12,
                }}
                title="true branch"
              />
              <Handle
                type="source"
                position={Position.Bottom}
                id="false"
                style={{
                  left: '70%',
                  backgroundColor: 'var(--color-danger)',
                  borderColor: 'var(--color-surface)',
                  width: 12,
                  height: 12,
                }}
                title="false branch"
              />
            </>
          ) : (
            <Handle
              type="source"
              position={Position.Bottom}
              style={{
                backgroundColor: 'var(--color-surface)',
                borderColor: 'var(--color-border)',
              }}
            />
          )}
        </>
      )}
    </div>
  )
}
