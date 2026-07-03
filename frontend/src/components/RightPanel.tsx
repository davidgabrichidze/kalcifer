import { type ToolActivity } from '../lib/chat'
import { type Artifact } from './ArtifactPanel'
import RightSidebar, { type ContextItem } from './RightSidebar'
import FlowCanvas from './FlowCanvas'
import FlowEditorInline from './FlowEditorInline'
import { type ContextContent } from '../pages/WorkPage'

interface RightPanelProps {
  mode: 'sidebar' | 'editor'
  // Sidebar props
  progressSteps: ToolActivity[]
  artifacts: Artifact[]
  contextItems: ContextItem[]
  onArtifactClick: (artifact: Artifact) => void
  isWorking?: boolean
  // Editor props
  editorContent: ContextContent
  /** Bumped when the AI mutates a flow graph — forwarded to the inline editor */
  editorRefreshToken?: number
  onBack: () => void
  onClose: () => void
  onOpenFullEditor?: (flowId: string) => void
}

export default function RightPanel({
  mode,
  progressSteps,
  artifacts,
  contextItems,
  onArtifactClick,
  isWorking = false,
  editorContent,
  editorRefreshToken,
  onBack,
  onClose,
  onOpenFullEditor,
}: RightPanelProps) {
  if (mode === 'sidebar') {
    return (
      <div className="right-panel right-panel--sidebar">
        <RightSidebar
          progressSteps={progressSteps}
          artifacts={artifacts}
          contextItems={contextItems}
          onArtifactClick={onArtifactClick}
          isWorking={isWorking}
        />
      </div>
    )
  }

  // Editor mode
  const editorTitle = editorContent?.type === 'flow-editor'
    ? 'Flow Editor'
    : editorContent?.type === 'flow-canvas'
      ? 'Flow Graph'
      : 'Editor'

  return (
    <div className="right-panel right-panel--editor">
      {/* Editor header */}
      <div className="right-editor-header">
        <button
          className="right-editor-btn"
          onClick={onBack}
          title="უკან"
        >
          ←
        </button>
        <span className="right-editor-title">{editorTitle}</span>
        <button
          className="right-editor-btn"
          onClick={onClose}
          title="დახურვა"
        >
          ✕
        </button>
      </div>

      {/* Editor content */}
      <div style={{ flex: 1, minHeight: 0, overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
        {editorContent?.type === 'flow-canvas' && (
          <FlowCanvas
            flowGraph={editorContent.flowGraph}
            editable={false}
            showMiniMap={true}
            showControls={true}
          />
        )}

        {editorContent?.type === 'flow-editor' && (
          <FlowEditorInline
            flowId={editorContent.flowId}
            refreshToken={editorRefreshToken}
            onOpenFullEditor={onOpenFullEditor}
          />
        )}
      </div>

      {/* Editor footer */}
      {editorContent?.type === 'flow-canvas' && (
        <div className="right-editor-footer">
          <span>{editorContent.flowGraph.nodes.length} nodes</span>
          <span>·</span>
          <span>{editorContent.flowGraph.edges.length} edges</span>
        </div>
      )}
    </div>
  )
}
