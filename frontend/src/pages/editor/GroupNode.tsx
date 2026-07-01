import { memo } from 'react'
import { type NodeProps } from '@xyflow/react'

/**
 * Visual container for grouped nodes. Group membership is persisted in
 * each member node's config under `_editor.group`, so the backend graph
 * schema stays untouched — the container is reconstructed on load.
 */
export const GroupNode = memo(function GroupNode({ data, selected }: NodeProps) {
  const label = (data as { label?: string }).label || 'Group'

  return (
    <div className={`group-node ${selected ? 'group-node-selected' : ''}`}>
      <div className="group-node-label">{label}</div>
    </div>
  )
})
