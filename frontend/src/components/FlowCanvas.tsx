import { useCallback, useEffect, useRef, DragEvent as ReactDragEvent } from 'react'
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
  useReactFlow,
} from '@xyflow/react'
import '@xyflow/react/dist/style.css'
import { type FlowGraph } from '../lib/api'
import { FlowNode } from '../pages/editor/FlowNode'
import { convertGraphToReactFlow } from '../pages/editor/flowGraphUtils'
import { useUndoRedo } from '../pages/editor/useUndoRedo'
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
  /** Callback to expose undo/redo controls to parent */
  onUndoRedoChange?: (canUndo: boolean, canRedo: boolean) => void
  /** Map of node ID → warning messages for validation overlay */
  nodeWarnings?: Map<string, string[]>
  /** Set of node IDs that failed execution */
  failedNodes?: Set<string>
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
  onUndoRedoChange,
  nodeWarnings,
  failedNodes,
}: FlowCanvasProps) {
  const [nodes, setNodes, onNodesChange] = useNodesState<Node>([])
  const [edges, setEdges, onEdgesChange] = useEdgesState<Edge>([])
  const { getNodes, getEdges } = useReactFlow()
  const { takeSnapshot, undo, redo, canUndo, canRedo, clear } = useUndoRedo()
  const isRestoringRef = useRef(false)

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
    clear()
  }, [flowGraph, setNodes, setEdges, clear])

  // Apply simulation state and validation warnings to node data
  useEffect(() => {
    if (!simCompletedNodes && !simActiveNode && !nodeWarnings && !failedNodes) return
    isRestoringRef.current = true
    setNodes(nds =>
      nds.map(n => ({
        ...n,
        data: {
          ...n.data,
          simCompleted: simCompletedNodes?.has(n.id) ?? false,
          simActive: simActiveNode === n.id,
          warnings: nodeWarnings?.get(n.id) ?? null,
          failed: failedNodes?.has(n.id) ?? false,
        },
      })),
    )
    // Reset flag after React processes the update
    requestAnimationFrame(() => { isRestoringRef.current = false })
  }, [simCompletedNodes, simActiveNode, nodeWarnings, failedNodes, setNodes])

  // Notify parent of graph changes
  useEffect(() => {
    onGraphChange?.(nodes, edges)
  }, [nodes, edges, onGraphChange])

  // Notify parent of undo/redo availability
  useEffect(() => {
    onUndoRedoChange?.(canUndo(), canRedo())
  })

  // Wrap onNodesChange to snapshot before structural changes (add/remove)
  const handleNodesChange = useCallback(
    (changes: Parameters<typeof onNodesChange>[0]) => {
      if (!editable) return
      const hasStructuralChange = changes.some(
        c => c.type === 'remove' || c.type === 'add',
      )
      if (hasStructuralChange && !isRestoringRef.current) {
        takeSnapshot(getNodes(), getEdges())
      }
      onNodesChange(changes)
    },
    [editable, onNodesChange, takeSnapshot, getNodes, getEdges],
  )

  // Wrap onEdgesChange to snapshot before structural changes
  const handleEdgesChange = useCallback(
    (changes: Parameters<typeof onEdgesChange>[0]) => {
      if (!editable) return
      const hasStructuralChange = changes.some(
        c => c.type === 'remove' || c.type === 'add',
      )
      if (hasStructuralChange && !isRestoringRef.current) {
        takeSnapshot(getNodes(), getEdges())
      }
      onEdgesChange(changes)
    },
    [editable, onEdgesChange, takeSnapshot, getNodes, getEdges],
  )

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
      takeSnapshot(getNodes(), getEdges())
      setEdges(eds => addEdge(connection, eds))
    },
    [editable, setEdges, takeSnapshot, getNodes, getEdges],
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

        takeSnapshot(getNodes(), getEdges())

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
    [editable, setNodes, takeSnapshot, getNodes, getEdges],
  )

  // Keyboard shortcuts: Ctrl+Z (undo), Ctrl+Y/Ctrl+Shift+Z (redo), Delete/Backspace (delete)
  useEffect(() => {
    if (!editable) return

    const handler = (e: KeyboardEvent) => {
      const mod = e.metaKey || e.ctrlKey
      const target = e.target as HTMLElement
      // Don't intercept keyboard events from input fields
      if (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA') return

      if (mod && e.key === 'z' && !e.shiftKey) {
        e.preventDefault()
        const snapshot = undo(getNodes(), getEdges())
        if (snapshot) {
          isRestoringRef.current = true
          setNodes(snapshot.nodes)
          setEdges(snapshot.edges)
          requestAnimationFrame(() => { isRestoringRef.current = false })
        }
      } else if (mod && (e.key === 'y' || (e.key === 'z' && e.shiftKey))) {
        e.preventDefault()
        const snapshot = redo(getNodes(), getEdges())
        if (snapshot) {
          isRestoringRef.current = true
          setNodes(snapshot.nodes)
          setEdges(snapshot.edges)
          requestAnimationFrame(() => { isRestoringRef.current = false })
        }
      } else if (e.key === 'Delete' || e.key === 'Backspace') {
        const selected = getNodes().filter(n => n.selected)
        if (selected.length === 0) return
        e.preventDefault()
        takeSnapshot(getNodes(), getEdges())
        const selectedIds = new Set(selected.map(n => n.id))
        setNodes(nds => nds.filter(n => !selectedIds.has(n.id)))
        setEdges(eds =>
          eds.filter(e => !selectedIds.has(e.source) && !selectedIds.has(e.target)),
        )
      }
    }

    window.addEventListener('keydown', handler)
    return () => window.removeEventListener('keydown', handler)
  }, [editable, undo, redo, takeSnapshot, getNodes, getEdges, setNodes, setEdges])

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
        onNodesChange={editable ? handleNodesChange : undefined}
        onEdgesChange={editable ? handleEdgesChange : undefined}
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
