import {
  useCallback,
  useEffect,
  useState,
} from 'react'
import { useSearchParams } from 'react-router-dom'
import { type Node, type Edge } from '@xyflow/react'
import { fetchFlow, fetchFlowVersions, type FlowVersion } from '../../lib/api'
import FlowCanvas from '../../components/FlowCanvas'
import { NodePalette } from './NodePalette'
import { NodeConfigPanel } from './NodeConfigPanel'
import './editor.css'


export default function FlowEditorPage() {
  const [searchParams] = useSearchParams()
  const flowId = searchParams.get('flow') || ''

  // State
  const [flow, setFlow] = useState<any>(null)
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

  // Track graph changes for bottom bar stats
  const handleGraphChange = useCallback((nodes: Node[], edges: Edge[]) => {
    setNodeCount(nodes.length)
    setEdgeCount(edges.length)
  }, [])

  // Palette: add node (TODO: wire to FlowCanvas via ref or callback)
  const handleAddNodeFromPalette = useCallback(
    (_nodeType: string) => {
      // For now, close palette — full wiring will come with FlowCanvas ref API
      setPaletteOpen(false)
    },
    [],
  )

  // Config panel: save
  const handleConfigSave = useCallback(
    (_config: Record<string, unknown>) => {
      // TODO: wire to FlowCanvas for node updates
      setConfigOpen(false)
    },
    [],
  )

  // Config panel: delete
  const handleDeleteNode = useCallback(() => {
    // TODO: wire to FlowCanvas for node deletion
    setSelectedNodeId(null)
    setConfigOpen(false)
  }, [])

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
        <FlowCanvas
          flowGraph={flowVersion?.graph || null}
          editable={mode === 'edit'}
          onNodeSelect={handleNodeSelect}
          onGraphChange={handleGraphChange}
          showMiniMap={true}
          showControls={true}
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
        </div>

        <div className="editor-bottom-right">
          <div className="editor-sim-status">Ready</div>
        </div>
      </div>
    </div>
  )
}
