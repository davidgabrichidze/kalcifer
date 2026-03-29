import { useState, useCallback, useEffect, useRef } from 'react'
import { useSearchParams, useNavigate } from 'react-router-dom'
import ChatPanel from '../components/ChatPanel'
import Sidebar from '../components/Sidebar'
import WelcomeScreen from '../components/WelcomeScreen'
import RightPanel from '../components/RightPanel'
import DragHandle from '../components/DragHandle'
import { type Artifact } from '../components/ArtifactPanel'
import { type ContextItem } from '../components/RightSidebar'
import { type ToolActivity } from '../lib/chat'
import { fetchConversations, type SessionClassification, type FlowGraph } from '../lib/api'
import './work-stages.css'

/**
 * Stages (redesigned — 4 stages):
 * - welcome: no sidebar, centered welcome (first visit, zero conversations)
 * - lobby:   sidebar visible, centered welcome (has conversations, nothing selected)
 * - chat:    sidebar visible, chat active, right sidebar (300px fixed)
 * - split:   sidebar collapsed, chat + editor side-by-side (drag-to-resize)
 */
type Stage = 'welcome' | 'lobby' | 'chat' | 'split'

/**
 * Right panel mode:
 * - hidden: no right panel (welcome/lobby)
 * - sidebar: 300px fixed sidebar with progress/artifacts/context
 * - editor: flex-based editor with flow canvas or editor
 */
type RightMode = 'hidden' | 'sidebar' | 'editor'

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

  // Right panel state
  const [rightMode, setRightMode] = useState<RightMode>('hidden')
  const [splitRatio, setSplitRatio] = useState(0.45)
  const [contextContent, setContextContent] = useState<ContextContent>(null)
  const mainRef = useRef<HTMLDivElement>(null)

  // Artifacts — collected from tool results during conversation
  const [artifacts, setArtifacts] = useState<Artifact[]>([])

  // Progress steps — tool activities for sidebar progress section
  const [progressSteps, setProgressSteps] = useState<ToolActivity[]>([])
  const [isWorking] = useState(false)

  // Context items — skills/meta for sidebar
  const [contextItems] = useState<ContextItem[]>([])

  // Unread tracking: lastSeenMap records when user last viewed each conversation
  const [lastSeenMap, setLastSeenMap] = useState<Map<string, string>>(new Map())

  // On mount: check URL for conversation ID, or check if conversations exist
  useEffect(() => {
    if (initializedRef.current) return
    initializedRef.current = true

    const urlConvId = searchParams.get('c')

    const now = new Date().toISOString()
    if (urlConvId) {
      setConversationId(urlConvId)
      setLastSeenMap(new Map([[urlConvId, now]]))
      setStage('chat')
      setRightMode('sidebar')
    } else {
      fetchConversations({ status: 'all' }).then(convs => {
        if (convs.length > 0) {
          const latest = convs[0]!
          setConversationId(latest.id)
          setLastSeenMap(new Map([[latest.id, now]]))
          setSearchParams({ c: latest.id }, { replace: true })
          setStage('chat')
          setRightMode('sidebar')
        }
      }).catch(() => {
        // API error — stay in welcome
      })
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  // Periodic sidebar refresh (detect background AI completions)
  useEffect(() => {
    if (stage === 'welcome') return
    const interval = setInterval(() => {
      setSidebarRefreshKey(k => k + 1)
    }, 10_000)
    return () => clearInterval(interval)
  }, [stage])

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
    setRightMode('sidebar')
    setInitialMessage(text)
  }, [])

  // Mark current conversation as seen
  const markSeen = useCallback((id: string) => {
    setLastSeenMap(prev => {
      const next = new Map(prev)
      next.set(id, new Date().toISOString())
      return next
    })
  }, [])

  // Sidebar: select existing conversation
  const handleSelectConversation = useCallback((id: string) => {
    setStage('chat')
    setRightMode('sidebar')
    setConversationId(id)
    markSeen(id)
    setSessionKind(null)
    setInitialMessage(null)
    setContextContent(null)
    setArtifacts([])
    setProgressSteps([])
    syncUrl(id)
  }, [syncUrl, markSeen])

  // New session from sidebar or chat — go to lobby (sidebar stays visible)
  const handleNewSession = useCallback(() => {
    setStage('lobby')
    setRightMode('hidden')
    setConversationId(null)
    setSessionKind(null)
    setInitialMessage(null)
    setContextContent(null)
    setArtifacts([])
    setProgressSteps([])
    syncUrl(null)
  }, [syncUrl])

  // Chat panel: got a conversation ID from backend
  const handleConversationId = useCallback((id: string) => {
    setConversationId(id)
    markSeen(id)
    syncUrl(id)
    setSidebarRefreshKey(k => k + 1)
  }, [syncUrl, markSeen])

  // Chat panel: session classified — if flow kind with flow_id, open editor
  const handleSessionClassified = useCallback((classification: SessionClassification) => {
    setSessionKind(classification)
    setSidebarRefreshKey(k => k + 1)

    // Auto-open flow editor when session is about a specific flow
    if (classification.flow_id && (classification.kind === 'flow' || classification.kind === 'campaign')) {
      setContextContent({ type: 'flow-editor', flowId: classification.flow_id })
      setStage('split')
      setRightMode('editor')
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
      setRightMode('hidden')
      setStage('lobby')
      syncUrl(null)
    }
  }, [conversationId, syncUrl])

  // Context area: receive content from ChatPanel (tool results) → open editor
  const handleContextContent = useCallback((content: ContextContent) => {
    setContextContent(content)
    setStage('split')
    setRightMode('editor')
  }, [])

  // Editor: back → return to sidebar mode
  const handleBack = useCallback(() => {
    setRightMode('sidebar')
    setStage('chat')
  }, [])

  // Editor: close → return to sidebar mode
  const handleClose = useCallback(() => {
    setContextContent(null)
    setRightMode('sidebar')
    setStage('chat')
  }, [])

  // Artifact: add new (deduplicate by id)
  const handleArtifact = useCallback((artifact: Artifact) => {
    setArtifacts(prev => {
      const exists = prev.findIndex(a => a.id === artifact.id)
      if (exists >= 0) {
        const updated = [...prev]
        updated[exists] = artifact
        return updated
      }
      return [...prev, artifact]
    })
  }, [])

  // Artifact clicked in sidebar — open corresponding content in editor
  const handleArtifactClick = useCallback((artifact: Artifact) => {
    switch (artifact.type) {
      case 'flow':
        if (artifact.resourceId) {
          setContextContent({ type: 'flow-editor', flowId: artifact.resourceId })
          setStage('split')
          setRightMode('editor')
        }
        break
      case 'graph':
        if (artifact.data?.graph) {
          setContextContent({ type: 'flow-canvas', flowGraph: artifact.data.graph as FlowGraph })
          setStage('split')
          setRightMode('editor')
        }
        break
      case 'analysis':
      case 'debug':
      case 'memory':
        break
    }
  }, [])

  // Open full editor page for a flow
  const handleOpenFullEditor = useCallback((flowId: string) => {
    navigate(`/editor?flow=${flowId}`)
  }, [navigate])

  // Drag handler for split mode
  const handleDrag = useCallback((clientX: number) => {
    const rect = mainRef.current?.getBoundingClientRect()
    if (!rect) return
    const sidebarW = stage === 'split' ? 52 : 210
    const ratio = (clientX - rect.left - sidebarW) / (rect.width - sidebarW)
    setSplitRatio(Math.max(0.2, Math.min(0.8, ratio)))
  }, [stage])

  const showSidebar = stage !== 'welcome'
  const showWelcome = stage === 'welcome' || stage === 'lobby'
  const showChat = stage === 'chat' || stage === 'split'
  const isEditorMode = rightMode === 'editor'

  return (
    <div
      ref={mainRef}
      className="work-stage"
      data-stage={stage}
      style={isEditorMode ? { '--split-ratio': splitRatio } as React.CSSProperties : undefined}
    >
      {/* Sidebar — visible in lobby, chat, split */}
      {showSidebar && (
        <Sidebar
          activeConversationId={conversationId}
          onSelectConversation={handleSelectConversation}
          onNewSession={handleNewSession}
          onConversationRemoved={handleConversationRemoved}
          refreshKey={sidebarRefreshKey}
          lastSeenMap={lastSeenMap}
          collapsed={stage === 'split'}
        />
      )}

      {/* Chat area */}
      <div
        className="work-chat"
        style={isEditorMode ? { flex: splitRatio } : undefined}
      >
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
      </div>

      {/* Drag handle — visible only in split/editor mode */}
      {isEditorMode && (
        <DragHandle onDrag={handleDrag} />
      )}

      {/* Right panel — sidebar or editor */}
      {rightMode !== 'hidden' && (
        <RightPanel
          mode={rightMode === 'editor' ? 'editor' : 'sidebar'}
          progressSteps={progressSteps}
          artifacts={artifacts}
          contextItems={contextItems}
          onArtifactClick={handleArtifactClick}
          isWorking={isWorking}
          editorContent={contextContent}
          onBack={handleBack}
          onClose={handleClose}
          onOpenFullEditor={handleOpenFullEditor}
        />
      )}
    </div>
  )
}
