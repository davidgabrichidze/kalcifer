import { useState, useCallback, useEffect, useRef } from 'react'
import { useSearchParams, useNavigate } from 'react-router-dom'
import ChatPanel from '../components/ChatPanel'
import FlowCanvas from '../components/FlowCanvas'
import FlowEditorInline from '../components/FlowEditorInline'
import Sidebar from '../components/Sidebar'
import WelcomeScreen from '../components/WelcomeScreen'
import ArtifactPanel, { type Artifact } from '../components/ArtifactPanel'
import { fetchConversations, type SessionClassification, type FlowGraph } from '../lib/api'
import './work-stages.css'

/**
 * Stages:
 * - welcome: no sidebar, centered welcome (first visit, zero conversations)
 * - lobby:   sidebar visible, centered welcome (has conversations, nothing selected)
 * - chat:    sidebar visible, chat active (conversation selected or just started)
 * - split:   chat + context side-by-side (context area visible, e.g. flow canvas)
 * - context: compact chat + full context (context area dominant)
 */
type Stage = 'welcome' | 'lobby' | 'chat' | 'split' | 'context'

/**
 * Context area content — discriminated union for different content types.
 * - flow-canvas: read-only flow graph preview (from tool results)
 * - flow-editor: interactive flow editor (when chat is about a specific flow)
 */
export type ContextContent =
  | { type: 'flow-canvas'; flowGraph: FlowGraph }
  | { type: 'flow-editor'; flowId: string }
  | null

export default function WorkPage() {
  const [searchParams, setSearchParams] = useSearchParams()
  const navigate = useNavigate()
  const [stage, setStage] = useState<Stage>('welcome')
  const [conversationId, setConversationId] = useState<string | null>(null)
  const [sessionKind, setSessionKind] = useState<SessionClassification | null>(null)
  const [initialMessage, setInitialMessage] = useState<string | null>(null)
  const [sidebarRefreshKey, setSidebarRefreshKey] = useState(0)
  const initializedRef = useRef(false)

  // Context area state
  const [contextContent, setContextContent] = useState<ContextContent>(null)
  const [contextScrollable, setContextScrollable] = useState(false)

  // Artifacts — collected from tool results during conversation
  const [artifacts, setArtifacts] = useState<Artifact[]>([])

  // On mount: check URL for conversation ID, or check if conversations exist
  useEffect(() => {
    if (initializedRef.current) return
    initializedRef.current = true

    const urlConvId = searchParams.get('c')

    if (urlConvId) {
      // URL has a conversation — go directly to chat
      setConversationId(urlConvId)
      setStage('chat')
    } else {
      // No URL param — check if there are existing conversations
      fetchConversations({ status: 'all' }).then(convs => {
        if (convs.length > 0) {
          // Has conversations — open the most recent one
          const latest = convs[0]!
          setConversationId(latest.id)
          setSearchParams({ c: latest.id }, { replace: true })
          setStage('chat')
        }
        // else: no conversations — stay in welcome
      }).catch(() => {
        // API error — stay in welcome
      })
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  // Sync conversationId → URL
  const syncUrl = useCallback((id: string | null) => {
    if (id) {
      setSearchParams({ c: id }, { replace: true })
    } else {
      setSearchParams({}, { replace: true })
    }
  }, [setSearchParams])

  // Welcome/lobby → chat transition: user sends first message
  const handleWelcomeSend = useCallback((text: string) => {
    setStage('chat')
    setInitialMessage(text)
  }, [])

  // Sidebar: select existing conversation
  const handleSelectConversation = useCallback((id: string) => {
    setStage('chat')
    setConversationId(id)
    setSessionKind(null)
    setInitialMessage(null)
    // Close context and clear artifacts when switching conversations
    setContextContent(null)
    setArtifacts([])
    syncUrl(id)
  }, [syncUrl])

  // New session from sidebar or chat — go to lobby (sidebar stays visible)
  const handleNewSession = useCallback(() => {
    setStage('lobby')
    setConversationId(null)
    setSessionKind(null)
    setInitialMessage(null)
    setContextContent(null)
    syncUrl(null)
  }, [syncUrl])

  // Chat panel: got a conversation ID from backend
  const handleConversationId = useCallback((id: string) => {
    setConversationId(id)
    syncUrl(id)
    setSidebarRefreshKey(k => k + 1)
  }, [syncUrl])

  // Chat panel: session classified — if flow kind with flow_id, open editor
  const handleSessionClassified = useCallback((classification: SessionClassification) => {
    setSessionKind(classification)
    setSidebarRefreshKey(k => k + 1)

    // Auto-open flow editor when session is about a specific flow
    if (classification.flow_id && (classification.kind === 'flow' || classification.kind === 'campaign')) {
      setContextContent({ type: 'flow-editor', flowId: classification.flow_id })
      setContextScrollable(false)
      setStage(prev => (prev === 'chat' || prev === 'lobby') ? 'split' : prev)
    }
  }, [])

  // Clear initial message after it's been consumed
  const handleInitialMessageSent = useCallback(() => {
    setInitialMessage(null)
  }, [])

  // Sidebar removed a conversation — refresh + handle if it was active
  const handleConversationRemoved = useCallback((removedId: string) => {
    setSidebarRefreshKey(k => k + 1)
    if (conversationId === removedId) {
      setConversationId(null)
      setSessionKind(null)
      setContextContent(null)
      setStage('lobby')
      syncUrl(null)
    }
  }, [conversationId, syncUrl])

  // Context area: receive content from ChatPanel (tool results)
  const handleContextContent = useCallback((content: ContextContent) => {
    setContextContent(content)
    setContextScrollable(content?.type !== 'flow-canvas' && content?.type !== 'flow-editor')
    if (stage === 'chat' || stage === 'lobby') {
      setStage('split')
    }
  }, [stage])

  // Context area: close → back to chat
  const handleCloseContext = useCallback(() => {
    setContextContent(null)
    setStage('chat')
  }, [])

  // Context area: toggle split ↔ context
  const handleToggleExpand = useCallback(() => {
    setStage(s => s === 'split' ? 'context' : 'split')
  }, [])

  // Artifact: add new (deduplicate by id)
  const handleArtifact = useCallback((artifact: Artifact) => {
    setArtifacts(prev => {
      const exists = prev.findIndex(a => a.id === artifact.id)
      if (exists >= 0) {
        // Update existing
        const updated = [...prev]
        updated[exists] = artifact
        return updated
      }
      return [...prev, artifact]
    })
  }, [])

  // Artifact clicked — open corresponding content
  const handleArtifactClick = useCallback((artifact: Artifact) => {
    switch (artifact.type) {
      case 'flow':
        if (artifact.resourceId) {
          setContextContent({ type: 'flow-editor', flowId: artifact.resourceId })
          setContextScrollable(false)
          if (stage === 'chat' || stage === 'lobby') setStage('split')
        }
        break
      case 'graph':
        if (artifact.data?.graph) {
          setContextContent({ type: 'flow-canvas', flowGraph: artifact.data.graph as FlowGraph })
          setContextScrollable(false)
          if (stage === 'chat' || stage === 'lobby') setStage('split')
        }
        break
      case 'analysis':
      case 'debug':
      case 'memory':
        // For non-visual artifacts, could show detail panel in future
        // For now, just log
        break
    }
  }, [stage])

  // Open full editor page for a flow
  const handleOpenFullEditor = useCallback((flowId: string) => {
    navigate(`/editor?flow=${flowId}`)
  }, [navigate])

  const showSidebar = stage !== 'welcome'
  const showWelcome = stage === 'welcome' || stage === 'lobby'
  const showChat = stage === 'chat' || stage === 'split' || stage === 'context'
  const showContext = stage === 'split' || stage === 'context'

  return (
    <div
      className="work-stage"
      data-stage={stage}
    >
      {/* Sidebar — visible in lobby, chat, split, context */}
      {showSidebar && (
        <Sidebar
          activeConversationId={conversationId}
          onSelectConversation={handleSelectConversation}
          onNewSession={handleNewSession}
          onConversationRemoved={handleConversationRemoved}
          refreshKey={sidebarRefreshKey}
        />
      )}

      {/* Chat area */}
      <div className="work-chat">
        {showWelcome && (
          <WelcomeScreen onSend={handleWelcomeSend} />
        )}

        {showChat && (
          <div className="chat-col" style={{ display: 'flex', flex: 1 }}>
            <ChatPanel
              conversationId={conversationId}
              sessionKind={sessionKind}
              onConversationId={handleConversationId}
              onSessionClassified={handleSessionClassified}
              initialMessage={initialMessage}
              onInitialMessageSent={handleInitialMessageSent}
              onContextContent={handleContextContent}
              onArtifact={handleArtifact}
            />
          </div>
        )}

        {/* Artifact panel — right sidebar with collected artifacts */}
        {showChat && artifacts.length > 0 && (
          <ArtifactPanel
            artifacts={artifacts}
            onArtifactClick={handleArtifactClick}
          />
        )}
      </div>

      {/* Resize handle — visible only in split/context */}
      {showContext && (
        <div className="work-resize-handle" />
      )}

      {/* Context area */}
      <div className={`work-context-area ${contextScrollable ? 'scrollable' : ''}`}>
        {/* Context header with expand/close buttons */}
        {showContext && (
          <div className="work-context-header">
            <button
              className="work-context-btn"
              onClick={handleToggleExpand}
              title={stage === 'split' ? 'გადიდება' : 'შემცირება'}
            >
              {stage === 'split' ? '⤢' : '⤡'}
            </button>
            <button
              className="work-context-btn"
              onClick={handleCloseContext}
              title="დახურვა"
            >
              ✕
            </button>
          </div>
        )}

        {/* Dynamic content rendering */}
        {contextContent?.type === 'flow-canvas' && (
          <FlowCanvas
            flowGraph={contextContent.flowGraph}
            editable={false}
            showMiniMap={stage === 'context'}
            showControls={true}
          />
        )}

        {contextContent?.type === 'flow-editor' && (
          <FlowEditorInline
            flowId={contextContent.flowId}
            onOpenFullEditor={handleOpenFullEditor}
          />
        )}
      </div>
    </div>
  )
}
