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
import { GroupNode } from '../pages/editor/GroupNode'
import { convertGraphToReactFlow } from '../pages/editor/flowGraphUtils'
import { useUndoRedo } from '../pages/editor/useUndoRedo'
import './flow-canvas.css'

const nodeTypes = {
  flowNode: FlowNode,
  groupNode: GroupNode,
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
  /** Map of node ID → analytics data for overlay badges */
  nodeAnalytics?: Map<string, { executed: number; completed: number; failed: number; avg_duration_ms?: number | null }>
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
  nodeAnalytics,
}: FlowCanvasProps) {
  const [nodes, setNodes, onNodesChange] = useNodesState<Node>([])
  const [edges, setEdges, onEdgesChange] = useEdgesState<Edge>([])
  const { getNodes, getEdges } = useReactFlow()
  const { takeSnapshot, undo, redo, canUndo, canRedo, clear } = useUndoRedo()
  const isRestoringRef = useRef(false)
  const clipboardRef = useRef<{ nodes: Node[]; edges: Edge[] } | null>(null)

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

  // Apply simulation state, validation warnings, and analytics to node data
  useEffect(() => {
    if (!simCompletedNodes && !simActiveNode && !nodeWarnings && !failedNodes && !nodeAnalytics) return
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
          analytics: nodeAnalytics?.get(n.id) ?? null,
        },
      })),
    )
    // Reset flag after React processes the update
    requestAnimationFrame(() => { isRestoringRef.current = false })
  }, [simCompletedNodes, simActiveNode, nodeWarnings, failedNodes, nodeAnalytics, setNodes])

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
    (_: React.MouseEvent, node: Node) => {
      if (node.type === 'groupNode') return
      const data = node.data as Record<string, unknown>
      onNodeSelect?.(node.id, {
        type: (data.type as string) || '',
        label: (data.label as string) || '',
        description: (data.description as string) || '',
        config: (data.config as Record<string, unknown>) || {},
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
      } else if (mod && e.key === 'c') {
        // Copy selected nodes + internal edges
        const selected = getNodes().filter(n => n.selected)
        if (selected.length === 0) return
        e.preventDefault()
        const selectedIds = new Set(selected.map(n => n.id))
        const internalEdges = getEdges().filter(
          edge => selectedIds.has(edge.source) && selectedIds.has(edge.target),
        )
        clipboardRef.current = {
          nodes: selected.map(n => ({ ...n })),
          edges: internalEdges.map(edge => ({ ...edge })),
        }
      } else if (mod && e.key === 'v') {
        // Paste from clipboard with new IDs + offset
        if (!clipboardRef.current || clipboardRef.current.nodes.length === 0) return
        e.preventDefault()
        takeSnapshot(getNodes(), getEdges())

        const OFFSET = 40
        const idMap = new Map<string, string>()
        const now = Date.now()

        const newNodes = clipboardRef.current.nodes.map((n, i) => {
          const newId = `${n.id}-copy-${now}-${i}`
          idMap.set(n.id, newId)
          return {
            ...n,
            id: newId,
            position: { x: n.position.x + OFFSET, y: n.position.y + OFFSET },
            selected: true,
          }
        })

        const newEdges = clipboardRef.current.edges
          .map(edge => {
            const newSource = idMap.get(edge.source)
            const newTarget = idMap.get(edge.target)
            if (!newSource || !newTarget) return null
            return {
              ...edge,
              id: `${edge.id}-copy-${now}`,
              source: newSource,
              target: newTarget,
            }
          })
          .filter((e): e is Edge => e !== null)

        // Deselect existing nodes, add new ones
        setNodes(nds => [
          ...nds.map(n => ({ ...n, selected: false })),
          ...newNodes,
        ])
        setEdges(eds => [...eds, ...newEdges])
      } else if (mod && e.key === 'g' && !e.shiftKey) {
        // Group selected nodes into a visual container
        const selected = getNodes().filter(
          n => n.selected && n.type === 'flowNode' && !n.parentId,
        )
        if (selected.length < 2) return
        e.preventDefault()
        takeSnapshot(getNodes(), getEdges())

        const PAD = 40
        const width = (n: Node) => n.measured?.width ?? 220
        const height = (n: Node) => n.measured?.height ?? 90
        const minX = Math.min(...selected.map(n => n.position.x)) - PAD
        const minY = Math.min(...selected.map(n => n.position.y)) - PAD
        const maxX = Math.max(...selected.map(n => n.position.x + width(n))) + PAD
        const maxY = Math.max(...selected.map(n => n.position.y + height(n))) + PAD

        const groupId = `group-${Date.now()}`
        const groupNode: Node = {
          id: groupId,
          type: 'groupNode',
          position: { x: minX, y: minY },
          style: { width: maxX - minX, height: maxY - minY },
          data: { label: 'Group' },
        }

        const selectedIds = new Set(selected.map(n => n.id))
        setNodes(nds => [
          ...nds.filter(n => !selectedIds.has(n.id)),
          groupNode,
          ...nds
            .filter(n => selectedIds.has(n.id))
            .map(n => ({
              ...n,
              parentId: groupId,
              extent: 'parent' as const,
              position: { x: n.position.x - minX, y: n.position.y - minY },
              selected: false,
            })),
        ])
      } else if (mod && e.key === 'g' && e.shiftKey) {
        // Ungroup: selected group containers, or the groups of selected members
        const all = getNodes()
        const selectedGroups = all.filter(n => n.selected && n.type === 'groupNode')
        const memberGroups = all
          .filter(n => n.selected && n.parentId)
          .map(n => n.parentId as string)
        const groupIds = new Set([...selectedGroups.map(n => n.id), ...memberGroups])
        if (groupIds.size === 0) return
        e.preventDefault()
        takeSnapshot(all, getEdges())

        const origins = new Map(
          all.filter(n => groupIds.has(n.id)).map(n => [n.id, n.position]),
        )

        setNodes(nds =>
          nds
            .filter(n => !groupIds.has(n.id))
            .map(n => {
              if (!n.parentId || !groupIds.has(n.parentId)) return n
              const origin = origins.get(n.parentId) || { x: 0, y: 0 }
              const { parentId: _parentId, extent: _extent, ...rest } = n
              return {
                ...rest,
                position: { x: n.position.x + origin.x, y: n.position.y + origin.y },
              }
            }),
        )
      } else if (e.key === 'Delete' || e.key === 'Backspace') {
        const selected = getNodes().filter(n => n.selected)
        if (selected.length === 0) return
        e.preventDefault()
        takeSnapshot(getNodes(), getEdges())
        const selectedIds = new Set(selected.map(n => n.id))
        const deletedGroupIds = new Set(
          selected.filter(n => n.type === 'groupNode').map(n => n.id),
        )
        const origins = new Map(
          selected.filter(n => n.type === 'groupNode').map(n => [n.id, n.position]),
        )
        setNodes(nds =>
          nds
            .filter(n => !selectedIds.has(n.id))
            .map(n => {
              // Deleting a group frees its children instead of orphaning them
              if (!n.parentId || !deletedGroupIds.has(n.parentId)) return n
              const origin = origins.get(n.parentId) || { x: 0, y: 0 }
              const { parentId: _parentId, extent: _extent, ...rest } = n
              return {
                ...rest,
                position: { x: n.position.x + origin.x, y: n.position.y + origin.y },
              }
            }),
        )
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
