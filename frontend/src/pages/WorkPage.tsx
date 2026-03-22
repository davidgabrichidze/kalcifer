import { useState, useCallback, useEffect, useRef } from 'react'
import { useSearchParams } from 'react-router-dom'
import ChatPanel from '../components/ChatPanel'
import Sidebar from '../components/Sidebar'
import WelcomeScreen from '../components/WelcomeScreen'
import { fetchConversations, type SessionClassification } from '../lib/api'

/**
 * Stages:
 * - welcome: no sidebar, centered welcome (first visit, zero conversations)
 * - lobby:   sidebar visible, centered welcome (has conversations, nothing selected)
 * - chat:    sidebar visible, chat active (conversation selected or just started)
 */
type Stage = 'welcome' | 'lobby' | 'chat'

export default function WorkPage() {
  const [searchParams, setSearchParams] = useSearchParams()
  const [stage, setStage] = useState<Stage>('welcome')
  const [conversationId, setConversationId] = useState<string | null>(null)
  const [sessionKind, setSessionKind] = useState<SessionClassification | null>(null)
  const [initialMessage, setInitialMessage] = useState<string | null>(null)
  const [sidebarRefreshKey, setSidebarRefreshKey] = useState(0)
  const initializedRef = useRef(false)

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
    syncUrl(id)
  }, [syncUrl])

  // New session from sidebar or chat — go to lobby (sidebar stays visible)
  const handleNewSession = useCallback(() => {
    setStage('lobby')
    setConversationId(null)
    setSessionKind(null)
    setInitialMessage(null)
    syncUrl(null)
  }, [syncUrl])

  // Chat panel: got a conversation ID from backend
  const handleConversationId = useCallback((id: string) => {
    setConversationId(id)
    syncUrl(id)
    setSidebarRefreshKey(k => k + 1)
  }, [syncUrl])

  // Chat panel: session classified
  const handleSessionClassified = useCallback((classification: SessionClassification) => {
    setSessionKind(classification)
    setSidebarRefreshKey(k => k + 1)
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
      setStage('lobby')
      syncUrl(null)
    }
  }, [conversationId, syncUrl])

  const showSidebar = stage !== 'welcome'
  const showWelcome = stage === 'welcome' || stage === 'lobby'
  const showChat = stage === 'chat'

  return (
    <div
      className="work-stage"
      data-stage={stage}
      style={{ display: 'flex', flex: 1, overflow: 'hidden', minHeight: 0 }}
    >
      {/* Sidebar — visible in lobby and chat */}
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
          <div className="chat-col" style={{ display: 'flex' }}>
            <ChatPanel
              conversationId={conversationId}
              sessionKind={sessionKind}
              onConversationId={handleConversationId}
              onSessionClassified={handleSessionClassified}
              initialMessage={initialMessage}
              onInitialMessageSent={handleInitialMessageSent}
            />
          </div>
        )}
      </div>
    </div>
  )
}
