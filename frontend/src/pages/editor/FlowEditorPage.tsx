import {
  useCallback,
  useEffect,
  useRef,
  useState,
} from 'react'
import { useSearchParams } from 'react-router-dom'
import { type Node, type Edge } from '@xyflow/react'
import { fetchFlow, fetchFlowVersions, simulateFlow, updateFlowVersion, preflightFlow, parseNodeWarnings, type Flow, type FlowVersion, type SimulationStep } from '../../lib/api'
import FlowCanvas, { type FlowCanvasHandle, type NodePatch } from '../../components/FlowCanvas'
import { useFlowSocket } from '../../lib/useFlowSocket'
import { NodePalette } from './NodePalette'
import { NodeConfigPanel } from './NodeConfigPanel'
import { convertReactFlowToGraph } from './flowGraphUtils'
import './editor.css'


export default function FlowEditorPage() {
  const [searchParams] = useSearchParams()
  const flowId = searchParams.get('flow') || ''

  // State
  const [flow, setFlow] = useState<Flow | null>(null)
  const [flowVersion, setFlowVersion] = useState<FlowVersion | null>(null)
  const [_loading, setLoading] = useState(true)
  const [_error, setError] = useState<string | null>(null)

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

  // Track node/edge counts from FlowCanvas
  const [nodeCount, setNodeCount] = useState(0)
  const [edgeCount, setEdgeCount] = useState(0)

  // Save state
  const [saving, setSaving] = useState(false)
  const [hasChanges, setHasChanges] = useState(false)
  const latestNodesRef = useRef<Node[]>([])
  const latestEdgesRef = useRef<Edge[]>([])
  const canvasRef = useRef<FlowCanvasHandle>(null)

  // Undo/redo state
  const [canUndo, setCanUndo] = useState(false)
  const [canRedo, setCanRedo] = useState(false)

  // Live mode — WebSocket connection
  const {
    connected: liveConnected,
    operators: liveOperators,
    activeInstances: liveActiveInstances,
    completedNodes: liveCompletedNodes,
    activeNodes: liveActiveNodes,
    failedNodes: liveFailedNodes,
  } = useFlowSocket({
    flowId: flowId || null,
    enabled: mode === 'live',
  })

  // Validation state
  const [validating, setValidating] = useState(false)
  const [nodeWarnings, setNodeWarnings] = useState<Map<string, string[]> | undefined>(undefined)
  const [validationSummary, setValidationSummary] = useState<string[] | null>(null)

  // Simulation state
  const [simStatus, setSimStatus] = useState<'idle' | 'running' | 'done' | 'failed'>('idle')
  const [simSteps, setSimSteps] = useState<SimulationStep[]>([])
  const [simActiveNode, setSimActiveNode] = useState<string | null>(null)
  const [simCompletedNodes, setSimCompletedNodes] = useState<Set<string>>(new Set())
  const [simDuration, setSimDuration] = useState<number | null>(null)
  const simAbortRef = useRef<AbortController | null>(null)

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
        }
      })
      .catch(err => {
        setError(err.message)
      })
      .finally(() => {
        setLoading(false)
      })
  }, [flowId])

  // Handle node selection from canvas
  const handleNodeSelect = useCallback(
    (nodeId: string, nodeData: { type: string; label: string; description: string; config: Record<string, unknown> }) => {
      setSelectedNodeId(nodeId)
      setSelectedNodeData(nodeData)
      setConfigOpen(true)
    },
    [],
  )

  // Track graph changes for bottom bar stats + save
  const handleGraphChange = useCallback((nodes: Node[], edges: Edge[]) => {
    setNodeCount(nodes.length)
    setEdgeCount(edges.length)
    latestNodesRef.current = nodes
    latestEdgesRef.current = edges
    setHasChanges(true)
  }, [])

  // Run preflight validation
  const runValidation = useCallback(async () => {
    if (!flowId || validating) return
    setValidating(true)
    try {
      const result = await preflightFlow(flowId)
      const warnings = parseNodeWarnings(result.warnings)
      setNodeWarnings(warnings.size > 0 ? warnings : undefined)
      setValidationSummary(result.warnings.length > 0 ? result.warnings : null)
    } catch (err) {
      console.error('Preflight failed:', err)
      setValidationSummary(['Validation failed — check console'])
    } finally {
      setValidating(false)
    }
  }, [flowId, validating])

  // Clear validation when graph changes
  useEffect(() => {
    if (hasChanges) {
      setNodeWarnings(undefined)
      setValidationSummary(null)
    }
  }, [hasChanges])

  // Undo/redo state updates from FlowCanvas
  const handleUndoRedoChange = useCallback((undo: boolean, redo: boolean) => {
    setCanUndo(undo)
    setCanRedo(redo)
  }, [])

  // Palette: add a node to the canvas
  const handleAddNodeFromPalette = useCallback(
    (nodeType: string) => {
      canvasRef.current?.addNode(nodeType)
      setPaletteOpen(false)
    },
    [],
  )

  // Config panel: apply an edit to the selected node (stays open for further edits)
  const handleConfigSave = useCallback(
    (patch: NodePatch) => {
      if (selectedNodeId) canvasRef.current?.updateNode(selectedNodeId, patch)
    },
    [selectedNodeId],
  )

  // Config panel: delete the selected node
  const handleDeleteNode = useCallback(() => {
    if (selectedNodeId) canvasRef.current?.deleteNode(selectedNodeId)
    setSelectedNodeId(null)
    setSelectedNodeData(null)
    setConfigOpen(false)
  }, [selectedNodeId])

  const saveGraph = useCallback(async () => {
    if (!flowId || !flowVersion || saving) return
    setSaving(true)
    try {
      const graph = convertReactFlowToGraph(
        latestNodesRef.current,
        latestEdgesRef.current,
        flowVersion.graph,
      )
      // Published versions are immutable — the API may return a new draft
      const saved = await updateFlowVersion(flowId, flowVersion.version_number, graph)
      setFlowVersion(saved)
      setHasChanges(false)
    } catch (err) {
      console.error('Save failed:', err)
    } finally {
      setSaving(false)
    }
  }, [flowId, flowVersion, saving])

  // Keyboard shortcut: Ctrl+S
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === 's') {
        e.preventDefault()
        saveGraph()
      }
    }
    window.addEventListener('keydown', handler)
    return () => window.removeEventListener('keydown', handler)
  }, [saveGraph])

  const startSimulation = useCallback(() => {
    if (!flowId || simStatus === 'running') return

    setSimStatus('running')
    setSimSteps([])
    setSimActiveNode(null)
    setSimCompletedNodes(new Set())
    setSimDuration(null)

    simAbortRef.current = simulateFlow(flowId, {
      onStart: () => {
        // Simulation started
      },
      onStep: (step) => {
        setSimSteps(prev => [...prev, step])
        setSimCompletedNodes(prev => new Set([...prev, step.node_id]))
        setSimActiveNode(step.node_id)
      },
      onDone: (data) => {
        setSimStatus(data.status === 'completed' ? 'done' : 'failed')
        setSimActiveNode(null)
        setSimDuration(data.duration_ms)
      },
      onError: (msg) => {
        setSimStatus('failed')
        setSimActiveNode(null)
        console.error('Simulation error:', msg)
      },
    })
  }, [flowId, simStatus])

  const stopSimulation = useCallback(() => {
    simAbortRef.current?.abort()
    setSimStatus('idle')
    setSimActiveNode(null)
  }, [])

  const resetSimulation = useCallback(() => {
    setSimStatus('idle')
    setSimSteps([])
    setSimActiveNode(null)
    setSimCompletedNodes(new Set())
    setSimDuration(null)
  }, [])

  // When switching to simulate mode, reset
  useEffect(() => {
    if (mode !== 'simulate') {
      resetSimulation()
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [mode])

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
          <button
            className="editor-top-btn"
            onClick={runValidation}
            disabled={validating}
            title="Validate flow (preflight check)"
          >
            {validating ? '...' : validationSummary === null && nodeWarnings === undefined ? 'Validate' : nodeWarnings && nodeWarnings.size > 0 ? `⚠ ${nodeWarnings.size}` : '✓ Valid'}
          </button>
          <button
            className={`editor-top-btn ${hasChanges ? 'has-changes' : ''}`}
            onClick={saveGraph}
            disabled={saving || !hasChanges}
            title="Save (Ctrl+S)"
          >
            {saving ? '...' : '💾 Save'}
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
        <FlowCanvas
          ref={canvasRef}
          flowGraph={flowVersion?.graph || null}
          editable={mode === 'edit'}
          onNodeSelect={handleNodeSelect}
          onGraphChange={handleGraphChange}
          showMiniMap={true}
          showControls={true}
          simCompletedNodes={
            mode === 'simulate' ? simCompletedNodes
            : mode === 'live' ? mergeCompletedNodes(liveCompletedNodes)
            : undefined
          }
          simActiveNode={
            mode === 'simulate' ? simActiveNode
            : mode === 'live' ? getFirstActiveNode(liveActiveNodes)
            : undefined
          }
          onUndoRedoChange={handleUndoRedoChange}
          nodeWarnings={nodeWarnings}
          failedNodes={mode === 'live' ? liveFailedNodes : undefined}
        />

        {/* Node Palette */}
        <NodePalette
          isOpen={paletteOpen}
          onClose={() => setPaletteOpen(false)}
          onAddNode={handleAddNodeFromPalette}
        />

        {/* Config Panel */}
        {selectedNodeData && (
          <NodeConfigPanel
            key={selectedNodeId}
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
            <strong>{nodeCount}</strong> nodes
          </div>
          <div className="editor-stats-pill">
            <div className="editor-stats-dot" style={{ background: 'var(--color-info)' }}></div>
            <strong>{edgeCount}</strong> edges
          </div>
          {mode === 'edit' && (canUndo || canRedo) && (
            <div className="editor-stats-pill" style={{ opacity: 0.7, fontSize: '10px' }}>
              {canUndo ? '↶' : ''} {canRedo ? '↷' : ''}
            </div>
          )}
          {validationSummary && validationSummary.length > 0 && (
            <div className="editor-stats-pill" style={{ color: 'var(--color-warn)', fontSize: '10px' }}>
              ⚠ {validationSummary.length} warning{validationSummary.length > 1 ? 's' : ''}
            </div>
          )}
        </div>

        <div className="editor-bottom-right">
          {mode === 'simulate' && (
            <div style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
              {simStatus === 'idle' && (
                <button className="editor-sim-btn" onClick={startSimulation}>
                  ▶ Dry Run
                </button>
              )}
              {simStatus === 'running' && (
                <button className="editor-sim-btn stop" onClick={stopSimulation}>
                  ■ Stop
                </button>
              )}
              {(simStatus === 'done' || simStatus === 'failed') && (
                <>
                  <span className="editor-sim-result">
                    {simStatus === 'done' ? '✓' : '✗'} {simSteps.length} steps
                    {simDuration != null && ` (${simDuration}ms)`}
                  </span>
                  <button className="editor-sim-btn" onClick={resetSimulation}>
                    ↺ Reset
                  </button>
                  <button className="editor-sim-btn" onClick={startSimulation}>
                    ▶ Re-run
                  </button>
                </>
              )}
            </div>
          )}
          <div className="editor-sim-status">
            {mode === 'simulate'
              ? simStatus === 'running' ? 'Simulating...' : simStatus === 'done' ? 'Done' : simStatus === 'failed' ? 'Failed' : 'Ready'
              : mode === 'live'
                ? liveConnected
                  ? `Live ${liveActiveInstances.size > 0 ? `(${liveActiveInstances.size} active)` : '(idle)'}${liveOperators.length > 1 ? ` · ${liveOperators.length} operators` : ''}`
                  : 'Connecting...'
                : 'Ready'}
          </div>
        </div>
      </div>
    </div>
  )
}

/** Merge all per-instance completed nodes into a single Set for canvas highlighting */
function mergeCompletedNodes(map: Map<string, Set<string>>): Set<string> {
  const merged = new Set<string>()
  for (const nodes of map.values()) {
    for (const nodeId of nodes) merged.add(nodeId)
  }
  return merged
}

/** Get the first active node across all active instances */
function getFirstActiveNode(map: Map<string, string | null>): string | null {
  for (const nodeId of map.values()) {
    if (nodeId) return nodeId
  }
  return null
}
