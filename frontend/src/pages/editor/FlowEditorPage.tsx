import {
  useCallback,
  useEffect,
  useState,
  DragEvent as ReactDragEvent,
} from 'react'
import { useSearchParams } from 'react-router-dom'
import {
  ReactFlow,
  Background,
  Controls,
  MiniMap,
  addEdge,
  type Connection,
  useNodesState,
  useEdgesState,
  type Node,
  type Edge,
  Panel,
} from '@xyflow/react'
import '@xyflow/react/dist/style.css'
import { fetchFlow, fetchFlowVersions, type FlowVersion, type FlowGraph, type FlowGraphNode } from '../../lib/api'
import { FlowNode } from './FlowNode'
import { NodePalette } from './NodePalette'
import { NodeConfigPanel } from './NodeConfigPanel'
import { getNodeType } from './nodeTypes'
import './editor.css'


const nodeTypes = {
  flowNode: FlowNode,
}

/**
 * Auto-layout algorithm: BFS from root nodes, assign positions in layers
 */
function autoLayoutNodes(
  graphNodes: Array<{ id: string; type: string }>,
  graphEdges: Array<{ source: string; target: string }>,
): Record<string, { x: number; y: number }> {
  const positions: Record<string, { x: number; y: number }> = {}

  if (graphNodes.length === 0) return positions

  // Find root nodes (no incoming edges)
  const hasIncoming = new Set(graphEdges.map(e => e.target))
  const roots = graphNodes.filter(n => !hasIncoming.has(n.id))

  if (roots.length === 0 && graphNodes.length > 0) {
    // If no roots, start from first node
    roots.push(graphNodes[0]!)
  }

  // BFS to assign layers
  const layers: Map<string, number> = new Map()
  const visited = new Set<string>()
  const queue: Array<[string, number]> = roots.map(r => [r.id, 0])

  while (queue.length > 0) {
    const [nodeId, layer] = queue.shift()!
    if (visited.has(nodeId)) continue

    visited.add(nodeId)
    layers.set(nodeId, layer)

    // Find children
    graphEdges.forEach(edge => {
      if (edge.source === nodeId && !visited.has(edge.target)) {
        queue.push([edge.target, layer + 1])
      }
    })
  }

  // Assign positions
  const nodesByLayer = new Map<number, string[]>()
  layers.forEach((layer, nodeId) => {
    if (!nodesByLayer.has(layer)) nodesByLayer.set(layer, [])
    nodesByLayer.get(layer)!.push(nodeId)
  })

  const LAYER_HEIGHT = 160
  const H_SPACING = 240

  nodesByLayer.forEach((nodeIds, layer) => {
    const totalWidth = nodeIds.length * H_SPACING
    const startX = -totalWidth / 2

    nodeIds.forEach((nodeId, index) => {
      positions[nodeId] = {
        x: startX + index * H_SPACING,
        y: layer * LAYER_HEIGHT,
      }
    })
  })

  return positions
}

/**
 * Extract a human-readable summary from a node's config.
 * Different node types store their key info in different config fields.
 */
function summarizeNodeConfig(gn: FlowGraphNode): string {
  const c = gn.config || {}
  switch (gn.type) {
    case 'send_email':
      return (c.subject as string) || (c.template_id as string) || ''
    case 'send_sms':
    case 'send_whatsapp':
      return (c.template_id as string) || (c.body as string) || ''
    case 'send_push':
      return (c.title as string) || ''
    case 'condition':
    case 'check_segment':
      return (c.expression as string) || (c.field as string) || (c.segment_field as string) || ''
    case 'wait':
      return (c.duration as string) || ''
    case 'wait_until':
      return (c.datetime as string) || (c.time as string) || ''
    case 'wait_for_event':
      return (c.event_name as string) || ''
    case 'ab_split':
      return Array.isArray(c.variants)
        ? (c.variants as Array<{ key?: string }>).map(v => v.key).filter(Boolean).join(' / ')
        : ''
    case 'call_webhook':
      return (c.url as string) || ''
    case 'add_tag':
      return (c.tag as string) || ''
    case 'segment_entry':
    case 'event_entry':
      return (c.event_name as string) || (c.segment as string) || ''
    default:
      return ''
  }
}

/**
 * Convert backend FlowGraph to React Flow nodes/edges with auto-layout
 */
function convertGraphToReactFlow(
  flowGraph: FlowGraph,
): { nodes: Node[]; edges: Edge[] } {
  const positions = autoLayoutNodes(flowGraph.nodes, flowGraph.edges)

  const nodes = flowGraph.nodes.map(gn => {
    const pos = positions[gn.id] || { x: 0, y: 0 }
    const nodeTypeMeta = getNodeType(gn.type)
    return {
      id: gn.id,
      type: 'flowNode',
      position: pos,
      data: {
        label: nodeTypeMeta?.label || gn.type,
        type: gn.type,
        description: summarizeNodeConfig(gn),
        configDetail: '',
      },
    } as Node
  })

  const edges = flowGraph.edges.map(ge => ({
    id: `${ge.source}-${ge.target}${ge.branch ? `-${ge.branch}` : ''}`,
    source: ge.source,
    target: ge.target,
    // Connect to the correct handle on branching nodes
    ...(ge.branch ? { sourceHandle: ge.branch } : {}),
    label: ge.branch || '',
    style: ge.branch === 'true'
      ? { stroke: 'var(--color-success)' }
      : ge.branch === 'false'
        ? { stroke: 'var(--color-danger)' }
        : {},
  }))

  return { nodes, edges }
}

export default function FlowEditorPage() {
  const [searchParams] = useSearchParams()
  const flowId = searchParams.get('flow') || ''

  // State
  const [flow, setFlow] = useState<any>(null)
  const [flowVersion, setFlowVersion] = useState<FlowVersion | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  // UI state
  const [mode, setMode] = useState<'edit' | 'simulate' | 'live'>('edit')
  const [paletteOpen, setPaletteOpen] = useState(false)
  const [configOpen, setConfigOpen] = useState(false)
  const [selectedNodeId, setSelectedNodeId] = useState<string | null>(null)
  const [selectedNodeData, setSelectedNodeData] = useState<{
    type: string
    label: string
    description: string
    config: Record<string, unknown>
  } | null>(null)

  // React Flow state
  const [nodes, setNodes, onNodesChange] = useNodesState<any>([])
  const [edges, setEdges, onEdgesChange] = useEdgesState<any>([])

  // Load flow data
  useEffect(() => {
    if (!flowId) {
      setLoading(false)
      return
    }

    Promise.all([fetchFlow(flowId), fetchFlowVersions(flowId)])
      .then(([flowData, versions]) => {
        setFlow(flowData)
        if (versions && versions.length > 0) {
          setFlowVersion(versions[0] || null)
          if (versions[0]) {
            const { nodes: rfNodes, edges: rfEdges } = convertGraphToReactFlow(versions[0].graph)
            setNodes(rfNodes)
            setEdges(rfEdges)
          }
        }
      })
      .catch(err => {
        setError(err.message)
      })
      .finally(() => {
        setLoading(false)
      })
  }, [flowId, setNodes, setEdges])

  // Handle node selection
  const handleNodeClick = useCallback(
    (_: any, node: Node) => {
      setSelectedNodeId(node.id)
      const data = node.data as Record<string, unknown>
      setSelectedNodeData({
        type: (data.type as string) || '',
        label: (data.label as string) || '',
        description: (data.description as string) || '',
        config: {},
      })
      setConfigOpen(true)
    },
    [],
  )

  // Handle edge connection
  const handleConnect = useCallback(
    (connection: Connection) => {
      setEdges(eds => addEdge(connection, eds))
    },
    [setEdges],
  )

  // Palette: add node
  const handleAddNodeFromPalette = useCallback(
    (nodeType: string) => {
      const newNode: Node = {
        id: `node-${Date.now()}`,
        type: 'flowNode',
        position: { x: 0, y: 0 },
        data: {
          label: nodeType,
          type: nodeType,
          description: '',
        },
      }
      setNodes(nds => [...nds, newNode])
      setPaletteOpen(false)
    },
    [setNodes],
  )

  // Canvas: drag over to show drop zone
  const handleCanvasDragOver = useCallback((e: ReactDragEvent) => {
    e.preventDefault()
    e.dataTransfer.dropEffect = 'move'
  }, [])

  // Canvas: drop to add node
  const handleCanvasDrop = useCallback(
    (e: ReactDragEvent) => {
      e.preventDefault()
      const data = e.dataTransfer.getData('application/json')
      if (!data) return

      try {
        const { type } = JSON.parse(data)
        const canvas = e.currentTarget as HTMLElement
        const rect = canvas.getBoundingClientRect()
        const x = e.clientX - rect.left
        const y = e.clientY - rect.top

        const newNode: Node = {
          id: `node-${Date.now()}`,
          type: 'flowNode',
          position: { x, y },
          data: {
            label: type,
            type,
            description: '',
          },
        }
        setNodes(nds => [...nds, newNode])
      } catch {
        // Invalid JSON
      }
    },
    [setNodes],
  )

  // Config panel: save
  const handleConfigSave = useCallback(
    (config: Record<string, unknown>) => {
      if (!selectedNodeId) return
      setNodes(nds =>
        nds.map(n =>
          n.id === selectedNodeId
            ? {
                ...n,
                data: { ...n.data, ...config },
              }
            : n,
        ),
      )
      setConfigOpen(false)
    },
    [selectedNodeId, setNodes],
  )

  // Config panel: delete
  const handleDeleteNode = useCallback(() => {
    if (!selectedNodeId) return
    setNodes(nds => nds.filter(n => n.id !== selectedNodeId))
    setEdges(eds =>
      eds.filter(
        e => (e.source !== selectedNodeId && e.target !== selectedNodeId) || false,
      ),
    )
    setSelectedNodeId(null)
    setConfigOpen(false)
  }, [selectedNodeId, setNodes, setEdges])

  const statusColor =
    flow?.status === 'draft'
      ? 'var(--color-info-soft)'
      : flow?.status === 'active'
        ? 'var(--color-success-soft)'
        : 'var(--color-warn-soft)'

  const statusTextColor =
    flow?.status === 'draft'
      ? 'var(--color-info)'
      : flow?.status === 'active'
        ? 'var(--color-success)'
        : 'var(--color-warn)'

  return (
    <div className="editor-container">
      {/* Topbar */}
      <div className="editor-topbar">
        <div className="editor-topbar-left">
          <div className="editor-logo">
            K<span className="editor-logo-sub">alcifer</span>
          </div>
          <div className="editor-flow-name-area">
            <input
              className="editor-flow-name-input"
              type="text"
              defaultValue={flow?.name || 'Untitled Flow'}
              placeholder="Flow name"
            />
            <span
              className="editor-flow-status"
              style={{ backgroundColor: statusColor, color: statusTextColor }}
            >
              {flow?.status?.charAt(0).toUpperCase() + (flow?.status?.slice(1) || 'Draft')}
            </span>
            <span className="editor-flow-version">
              v{flowVersion?.version_number || 1}
            </span>
          </div>
        </div>

        <div className="editor-topbar-center">
          <button
            className={`editor-mode-btn ${mode === 'edit' ? 'active' : ''}`}
            onClick={() => setMode('edit')}
          >
            ✎ Edit
          </button>
          <button
            className={`editor-mode-btn ${mode === 'simulate' ? 'active' : ''}`}
            onClick={() => setMode('simulate')}
          >
            ▶ Simulate
          </button>
          <button
            className={`editor-mode-btn ${mode === 'live' ? 'active' : ''}`}
            onClick={() => setMode('live')}
          >
            ◉ Live
          </button>
        </div>

        <div className="editor-topbar-right">
          <button className="editor-top-btn" onClick={() => (window.location.href = '/')}>
            ← Work
          </button>
          <button
            className="editor-top-btn"
            onClick={() => setPaletteOpen(!paletteOpen)}
            title="Toggle node palette"
          >
            + Node
          </button>
          <div className="editor-avatar">DG</div>
        </div>
      </div>

      {/* Main content */}
      <div className="editor-main">
        {/* Chat placeholder */}
        <div className="editor-chat-panel">
          <div className="editor-chat-header">
            <div className="editor-chat-header-left">
              <h3>Kalcifer</h3>
            </div>
            <button
              className="editor-chat-toggle"
              onClick={() => {
                /* toggle collapse */
              }}
              title="Collapse chat"
            >
              ☰
            </button>
          </div>
          <div className="editor-chat-body">
            <div className="editor-chat-placeholder">
              Ask me to build, edit, or analyze your flows
            </div>
          </div>
        </div>

        {/* Canvas */}
        <div
          className="editor-canvas"
          onDragOver={handleCanvasDragOver}
          onDrop={handleCanvasDrop}
        >
          <ReactFlow
            nodes={nodes}
            edges={edges}
            onNodesChange={onNodesChange}
            onEdgesChange={onEdgesChange}
            onConnect={handleConnect}
            onNodeClick={handleNodeClick}
            nodeTypes={nodeTypes}
            fitView
          >
            <Background />
            <Controls />
            <MiniMap />
            <Panel position="top-left" style={{ pointerEvents: 'none' }}>
              <div style={{ color: 'var(--color-text-muted)', fontSize: '12px' }}>
                {!loading && flowId === '' && 'No flow selected'}
                {loading && 'Loading flow...'}
                {error && `Error: ${error}`}
              </div>
            </Panel>
          </ReactFlow>
        </div>

        {/* Node Palette */}
        <NodePalette
          isOpen={paletteOpen}
          onClose={() => setPaletteOpen(false)}
          onAddNode={handleAddNodeFromPalette}
        />

        {/* Config Panel */}
        {selectedNodeData && (
          <NodeConfigPanel
            isOpen={configOpen}
            nodeId={selectedNodeId}
            nodeType={selectedNodeData.type}
            nodeLabel={selectedNodeData.label}
            nodeDescription={selectedNodeData.description}
            nodeConfig={selectedNodeData.config}
            onClose={() => setConfigOpen(false)}
            onSave={handleConfigSave}
            onDelete={handleDeleteNode}
          />
        )}
      </div>

      {/* Bottom bar */}
      <div className="editor-bottombar">
        <div className="editor-bottom-left">
          <div className="editor-stats-pill">
            <div className="editor-stats-dot" style={{ background: 'var(--color-success)' }}></div>
            <strong>{nodes.length}</strong> nodes
          </div>
          <div className="editor-stats-pill">
            <div className="editor-stats-dot" style={{ background: 'var(--color-info)' }}></div>
            <strong>{edges.length}</strong> edges
          </div>
        </div>

        <div className="editor-bottom-right">
          <div className="editor-sim-status">Ready</div>
        </div>
      </div>
    </div>
  )
}
