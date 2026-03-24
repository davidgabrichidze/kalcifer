import {
  useCallback,
  useEffect,
  useRef,
  useState,
} from 'react'
import { type Node, type Edge } from '@xyflow/react'
import {
  fetchFlow,
  fetchFlowVersions,
  fetchInstances,
  fetchInstanceTimeline,
  simulateFlow,
  updateFlowVersion,
  preflightFlow,
  parseNodeWarnings,
  type FlowVersion,
  type SimulationStep,
  type FlowInstanceSummary,
  type ExecutionStepData,
} from '../lib/api'
import FlowCanvas from './FlowCanvas'
import { useFlowSocket } from '../lib/useFlowSocket'
import { NodePalette } from '../pages/editor/NodePalette'
import { NodeConfigPanel } from '../pages/editor/NodeConfigPanel'
import { convertReactFlowToGraph } from '../pages/editor/flowGraphUtils'
import './flow-editor-inline.css'

interface FlowEditorInlineProps {
  flowId: string
  /** Called when the user clicks the "open in editor" button */
  onOpenFullEditor?: (flowId: string) => void
}

/**
 * Inline flow editor for the WorkPage context panel.
 * A compact version of FlowEditorPage — no standalone topbar, fits inside a panel.
 */
export default function FlowEditorInline({ flowId, onOpenFullEditor }: FlowEditorInlineProps) {
  // Flow data
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

  // Track counts
  const [nodeCount, setNodeCount] = useState(0)
  const [edgeCount, setEdgeCount] = useState(0)

  // Save state
  const [saving, setSaving] = useState(false)
  const [hasChanges, setHasChanges] = useState(false)
  const latestNodesRef = useRef<Node[]>([])
  const latestEdgesRef = useRef<Edge[]>([])

  // Undo/redo
  const [canUndo, setCanUndo] = useState(false)
  const [canRedo, setCanRedo] = useState(false)

  // Live mode
  const {
    connected: liveConnected,
    activeInstances: liveActiveInstances,
    completedNodes: liveCompletedNodes,
    activeNodes: liveActiveNodes,
    failedNodes: liveFailedNodes,
  } = useFlowSocket({
    flowId: flowId || null,
    enabled: mode === 'live',
  })

  // Validation
  const [validating, setValidating] = useState(false)
  const [nodeWarnings, setNodeWarnings] = useState<Map<string, string[]> | undefined>(undefined)
  const [validationSummary, setValidationSummary] = useState<string[] | null>(null)

  // Instance timeline overlay
  const [instances, setInstances] = useState<FlowInstanceSummary[]>([])
  const [selectedInstanceId, setSelectedInstanceId] = useState<string | null>(null)
  const [timeline, setTimeline] = useState<ExecutionStepData[]>([])
  const [timelineCompletedNodes, setTimelineCompletedNodes] = useState<Set<string>>(new Set())
  const [timelineFailedNodes, setTimelineFailedNodes] = useState<Set<string>>(new Set())
  const [showInstancePicker, setShowInstancePicker] = useState(false)

  // Simulation
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

    setLoading(true)
    setError(null)

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

  // Node selection
  const handleNodeSelect = useCallback(
    (nodeId: string, nodeData: { type: string; label: string; description: string; config: Record<string, unknown> }) => {
      setSelectedNodeId(nodeId)
      setSelectedNodeData(nodeData)
      setConfigOpen(true)
    },
    [],
  )

  // Graph changes
  const handleGraphChange = useCallback((nodes: Node[], edges: Edge[]) => {
    setNodeCount(nodes.length)
    setEdgeCount(edges.length)
    latestNodesRef.current = nodes
    latestEdgesRef.current = edges
    setHasChanges(true)
  }, [])

  // Validation
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

  // Clear validation on graph changes
  useEffect(() => {
    if (hasChanges) {
      setNodeWarnings(undefined)
      setValidationSummary(null)
    }
  }, [hasChanges])

  // Undo/redo tracking
  const handleUndoRedoChange = useCallback((undo: boolean, redo: boolean) => {
    setCanUndo(undo)
    setCanRedo(redo)
  }, [])

  // Palette
  const handleAddNodeFromPalette = useCallback((_nodeType: string) => {
    setPaletteOpen(false)
  }, [])

  // Config panel
  const handleConfigSave = useCallback((_config: Record<string, unknown>) => {
    setConfigOpen(false)
  }, [])

  const handleDeleteNode = useCallback(() => {
    setSelectedNodeId(null)
    setConfigOpen(false)
  }, [])

  // Save
  const saveGraph = useCallback(async () => {
    if (!flowId || !flowVersion || saving) return
    setSaving(true)
    try {
      const graph = convertReactFlowToGraph(
        latestNodesRef.current,
        latestEdgesRef.current,
        flowVersion.graph,
      )
      await updateFlowVersion(flowId, flowVersion.version_number, graph)
      setHasChanges(false)
    } catch (err) {
      console.error('Save failed:', err)
    } finally {
      setSaving(false)
    }
  }, [flowId, flowVersion, saving])

  // Ctrl+S
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

  // Simulation
  const startSimulation = useCallback(() => {
    if (!flowId || simStatus === 'running') return
    setSimStatus('running')
    setSimSteps([])
    setSimActiveNode(null)
    setSimCompletedNodes(new Set())
    setSimDuration(null)

    simAbortRef.current = simulateFlow(flowId, {
      onStart: () => {},
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

  useEffect(() => {
    if (mode !== 'simulate') resetSimulation()
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [mode])

  // Load instances list when entering live mode
  useEffect(() => {
    if (mode === 'live' && flowId) {
      fetchInstances(flowId, { limit: 20 })
        .then(setInstances)
        .catch(() => setInstances([]))
    } else {
      setInstances([])
      setSelectedInstanceId(null)
      setTimeline([])
      setTimelineCompletedNodes(new Set())
      setTimelineFailedNodes(new Set())
    }
  }, [mode, flowId])

  // Load timeline when instance selected
  useEffect(() => {
    if (!selectedInstanceId) {
      setTimeline([])
      setTimelineCompletedNodes(new Set())
      setTimelineFailedNodes(new Set())
      return
    }

    fetchInstanceTimeline(selectedInstanceId)
      .then(steps => {
        setTimeline(steps)
        const completed = new Set<string>()
        const failed = new Set<string>()
        for (const step of steps) {
          if (step.status === 'completed') completed.add(step.node_id)
          else if (step.status === 'failed') failed.add(step.node_id)
        }
        setTimelineCompletedNodes(completed)
        setTimelineFailedNodes(failed)
      })
      .catch(() => {
        setTimeline([])
        setTimelineCompletedNodes(new Set())
        setTimelineFailedNodes(new Set())
      })
  }, [selectedInstanceId])

  // ── Render ─────────────────────────────────

  if (loading) {
    return (
      <div className="fei-loading">
        <span className="fei-loading-dot" />
        იტვირთება...
      </div>
    )
  }

  if (error) {
    return (
      <div className="fei-error">
        ⚠ {error}
      </div>
    )
  }

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
    <div className="fei-container">
      {/* Compact toolbar */}
      <div className="fei-toolbar">
        <div className="fei-toolbar-left">
          <span className="fei-flow-name">{flow?.name || 'Untitled'}</span>
          <span
            className="fei-flow-status"
            style={{ backgroundColor: statusColor, color: statusTextColor }}
          >
            {flow?.status?.charAt(0).toUpperCase() + (flow?.status?.slice(1) || '')}
          </span>
          <span className="fei-flow-version">v{flowVersion?.version_number || 1}</span>
        </div>

        <div className="fei-toolbar-center">
          <button
            className={`fei-mode-btn ${mode === 'edit' ? 'active' : ''}`}
            onClick={() => setMode('edit')}
          >
            ✎
          </button>
          <button
            className={`fei-mode-btn ${mode === 'simulate' ? 'active' : ''}`}
            onClick={() => setMode('simulate')}
          >
            ▶
          </button>
          <button
            className={`fei-mode-btn ${mode === 'live' ? 'active' : ''}`}
            onClick={() => setMode('live')}
          >
            ◉
          </button>
        </div>

        <div className="fei-toolbar-right">
          <button
            className="fei-btn"
            onClick={() => setPaletteOpen(!paletteOpen)}
            title="ნაბიჯების პალიტრა"
          >
            +
          </button>
          <button
            className="fei-btn"
            onClick={runValidation}
            disabled={validating}
            title="ვალიდაცია"
          >
            {validating ? '...' : nodeWarnings && nodeWarnings.size > 0 ? `⚠${nodeWarnings.size}` : '✓'}
          </button>
          <button
            className={`fei-btn ${hasChanges ? 'has-changes' : ''}`}
            onClick={saveGraph}
            disabled={saving || !hasChanges}
            title="შენახვა (Ctrl+S)"
          >
            {saving ? '...' : '💾'}
          </button>
          {onOpenFullEditor && (
            <button
              className="fei-btn"
              onClick={() => onOpenFullEditor(flowId)}
              title="სრულ ედიტორში გახსნა"
            >
              ↗
            </button>
          )}
        </div>
      </div>

      {/* Canvas area */}
      <div className="fei-canvas-area">
        <FlowCanvas
          flowGraph={flowVersion?.graph || null}
          editable={mode === 'edit'}
          onNodeSelect={handleNodeSelect}
          onGraphChange={handleGraphChange}
          showMiniMap={true}
          showControls={true}
          simCompletedNodes={
            mode === 'simulate' ? simCompletedNodes
            : mode === 'live' && selectedInstanceId ? timelineCompletedNodes
            : mode === 'live' ? mergeCompletedNodes(liveCompletedNodes)
            : undefined
          }
          simActiveNode={
            mode === 'simulate' ? simActiveNode
            : mode === 'live' && !selectedInstanceId ? getFirstActiveNode(liveActiveNodes)
            : undefined
          }
          onUndoRedoChange={handleUndoRedoChange}
          nodeWarnings={nodeWarnings}
          failedNodes={
            mode === 'live' && selectedInstanceId ? timelineFailedNodes
            : mode === 'live' ? liveFailedNodes
            : undefined
          }
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

      {/* Bottom status bar */}
      <div className="fei-statusbar">
        <div className="fei-status-left">
          <span className="fei-stat">{nodeCount} ნაბ.</span>
          <span className="fei-stat">{edgeCount} კავ.</span>
          {mode === 'edit' && (canUndo || canRedo) && (
            <span className="fei-stat" style={{ opacity: 0.6 }}>
              {canUndo ? '↶' : ''} {canRedo ? '↷' : ''}
            </span>
          )}
          {validationSummary && validationSummary.length > 0 && (
            <span className="fei-stat fei-stat-warn">
              ⚠ {validationSummary.length}
            </span>
          )}
        </div>

        <div className="fei-status-right">
          {mode === 'simulate' && (
            <>
              {simStatus === 'idle' && (
                <button className="fei-sim-btn" onClick={startSimulation}>▶ Run</button>
              )}
              {simStatus === 'running' && (
                <button className="fei-sim-btn fei-sim-stop" onClick={stopSimulation}>■</button>
              )}
              {(simStatus === 'done' || simStatus === 'failed') && (
                <>
                  <span className="fei-stat">
                    {simStatus === 'done' ? '✓' : '✗'} {simSteps.length}
                    {simDuration != null && ` (${simDuration}ms)`}
                  </span>
                  <button className="fei-sim-btn" onClick={resetSimulation}>↺</button>
                  <button className="fei-sim-btn" onClick={startSimulation}>▶</button>
                </>
              )}
            </>
          )}

          {/* Instance timeline picker (live mode) */}
          {mode === 'live' && instances.length > 0 && (
            <div className="fei-instance-picker">
              <button
                className="fei-sim-btn"
                onClick={() => setShowInstancePicker(p => !p)}
                title="ინსტანსის შერჩევა"
              >
                {selectedInstanceId
                  ? `📋 ${timeline.length} steps`
                  : `📋 ${instances.length}`}
              </button>
              {selectedInstanceId && (
                <button
                  className="fei-sim-btn"
                  onClick={() => setSelectedInstanceId(null)}
                  title="overlay-ის გათიშვა"
                >
                  ✕
                </button>
              )}
              {showInstancePicker && (
                <div className="fei-instance-dropdown">
                  {instances.map(inst => (
                    <button
                      key={inst.id}
                      className={`fei-instance-item ${inst.id === selectedInstanceId ? 'active' : ''}`}
                      onClick={() => {
                        setSelectedInstanceId(inst.id)
                        setShowInstancePicker(false)
                      }}
                    >
                      <span className={`fei-instance-dot fei-dot-${inst.status}`} />
                      <span className="fei-instance-id">
                        {inst.customer_id || inst.id.slice(0, 8)}
                      </span>
                      <span className="fei-instance-status">{inst.status}</span>
                    </button>
                  ))}
                </div>
              )}
            </div>
          )}

          <span className="fei-mode-label">
            {mode === 'simulate'
              ? simStatus === 'running' ? '...' : simStatus === 'done' ? '✓' : simStatus === 'failed' ? '✗' : '▶'
              : mode === 'live'
                ? liveConnected
                  ? `◉ ${liveActiveInstances.size > 0 ? liveActiveInstances.size : ''}`
                  : '◌'
                : '✎'}
          </span>
        </div>
      </div>
    </div>
  )
}

function mergeCompletedNodes(map: Map<string, Set<string>>): Set<string> {
  const merged = new Set<string>()
  for (const nodes of map.values()) {
    for (const nodeId of nodes) merged.add(nodeId)
  }
  return merged
}

function getFirstActiveNode(map: Map<string, string | null>): string | null {
  for (const nodeId of map.values()) {
    if (nodeId) return nodeId
  }
  return null
}
