import { useCallback, useEffect, DragEvent as ReactDragEvent } from 'react'
import {
  ReactFlow,
  ReactFlowProvider,
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
import { type FlowGraph } from '../lib/api'
import { FlowNode } from '../pages/editor/FlowNode'
import { convertGraphToReactFlow } from '../pages/editor/flowGraphUtils'
import './flow-canvas.css'

const nodeTypes = {
  flowNode: FlowNode,
}

export interface FlowCanvasProps {
  flowGraph: FlowGraph | null
  editable?: boolean
  onGraphChange?: (nodes: Node[], edges: Edge[]) => void
  onNodeSelect?: (nodeId: string, nodeData: {
    type: string
    label: string
    description: string
    config: Record<string, unknown>
  }) => void
  showMiniMap?: boolean
  showControls?: boolean
  className?: string
  /** Set of node IDs that have completed simulation */
  simCompletedNodes?: Set<string>
  /** Currently active simulation node ID */
  simActiveNode?: string | null
}

function FlowCanvasInner({
  flowGraph,
  editable = false,
  onGraphChange,
  onNodeSelect,
  showMiniMap = true,
  showControls = true,
  className = '',
  simCompletedNodes,
  simActiveNode,
}: FlowCanvasProps) {
  const [nodes, setNodes, onNodesChange] = useNodesState<Node>([])
  const [edges, setEdges, onEdgesChange] = useEdgesState<Edge>([])

  // Convert flowGraph prop → React Flow nodes/edges
  useEffect(() => {
    if (!flowGraph) {
      setNodes([])
      setEdges([])
      return
    }
    const { nodes: rfNodes, edges: rfEdges } = convertGraphToReactFlow(flowGraph)
    setNodes(rfNodes)
    setEdges(rfEdges)
  }, [flowGraph, setNodes, setEdges])

  // Apply simulation state to node data
  useEffect(() => {
    if (!simCompletedNodes && !simActiveNode) return
    setNodes(nds =>
      nds.map(n => ({
        ...n,
        data: {
          ...n.data,
          simCompleted: simCompletedNodes?.has(n.id) ?? false,
          simActive: simActiveNode === n.id,
        },
      })),
    )
  }, [simCompletedNodes, simActiveNode, setNodes])

  // Notify parent of graph changes
  useEffect(() => {
    onGraphChange?.(nodes, edges)
  }, [nodes, edges, onGraphChange])

  const handleNodeClick = useCallback(
    (_: any, node: Node) => {
      const data = node.data as Record<string, unknown>
      onNodeSelect?.(node.id, {
        type: (data.type as string) || '',
        label: (data.label as string) || '',
        description: (data.description as string) || '',
        config: {},
      })
    },
    [onNodeSelect],
  )

  const handleConnect = useCallback(
    (connection: Connection) => {
      if (!editable) return
      setEdges(eds => addEdge(connection, eds))
    },
    [editable, setEdges],
  )

  const handleDragOver = useCallback(
    (e: ReactDragEvent) => {
      if (!editable) return
      e.preventDefault()
      e.dataTransfer.dropEffect = 'move'
    },
    [editable],
  )

  const handleDrop = useCallback(
    (e: ReactDragEvent) => {
      if (!editable) return
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
    [editable, setNodes],
  )

  const isEmpty = !flowGraph || flowGraph.nodes.length === 0

  return (
    <div
      className={`flow-canvas ${className}`}
      onDragOver={handleDragOver}
      onDrop={handleDrop}
    >
      <ReactFlow
        nodes={nodes}
        edges={edges}
        onNodesChange={editable ? onNodesChange : undefined}
        onEdgesChange={editable ? onEdgesChange : undefined}
        onConnect={handleConnect}
        onNodeClick={handleNodeClick}
        nodeTypes={nodeTypes}
        nodesDraggable={editable}
        nodesConnectable={editable}
        elementsSelectable={true}
        fitView
      >
        <Background />
        {showControls && <Controls />}
        {showMiniMap && <MiniMap />}
        {isEmpty && (
          <Panel position="top-left" style={{ pointerEvents: 'none' }}>
            <div style={{ color: 'var(--color-text-muted)', fontSize: '12px' }}>
              No flow graph loaded
            </div>
          </Panel>
        )}
      </ReactFlow>
    </div>
  )
}

export default function FlowCanvas(props: FlowCanvasProps) {
  return (
    <ReactFlowProvider>
      <FlowCanvasInner {...props} />
    </ReactFlowProvider>
  )
}
