import { useState, useCallback, useEffect, useRef } from 'react'
import { useSearchParams } from 'react-router-dom'
import ChatPanel from '../components/ChatPanel'
import Sidebar from '../components/Sidebar'
import WelcomeScreen from '../components/WelcomeScreen'
import { fetchConversations, type SessionClassification } from '../lib/api'

type Stage = 'welcome' | 'chat'

export default function WorkPage() {
  const [searchParams, setSearchParams] = useSearchParams()
  const [stage, setStage] = useState<Stage>('welcome')
  const [conversationId, setConversationId] = useState<string | null>(null)
  const [sessionKind, setSessionKind] = useState<SessionClassification | null>(null)
  const [initialMessage, setInitialMessage] = useState<string | null>(null)
  const [sidebarRefreshKey, setSidebarRefreshKey] = useState(0)
  const initializedRef = useRef(false)

  // On mount: check URL for conversation ID, or load most recent
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
      fetchConversations().then(convs => {
        const active = convs.filter(c => c.status === 'active')
        if (active.length > 0 && active[0]) {
          // Has conversations — show most recent in chat stage
          setConversationId(active[0].id)
          setStage('chat')
          setSearchParams({ c: active[0].id }, { replace: true })
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

  // Welcome → chat transition: user sends first message
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

  // New session from sidebar or chat
  const handleNewSession = useCallback(() => {
    setStage('welcome')
    setConversationId(null)
    setSessionKind(null)
    setInitialMessage(null)
    syncUrl(null)
  }, [syncUrl])

  // Chat panel: got a conversation ID from backend
  const handleConversationId = useCallback((id: string) => {
    setConversationId(id)
    syncUrl(id)
    // Refresh sidebar to show new conversation
    setSidebarRefreshKey(k => k + 1)
  }, [syncUrl])

  // Chat panel: session classified
  const handleSessionClassified = useCallback((classification: SessionClassification) => {
    setSessionKind(classification)
    // Refresh sidebar to show updated kind/title
    setSidebarRefreshKey(k => k + 1)
  }, [])

  // Clear initial message after it's been consumed
  const handleInitialMessageSent = useCallback(() => {
    setInitialMessage(null)
  }, [])

  return (
    <div
      className="work-stage"
      data-stage={stage}
      style={{ display: 'flex', flex: 1, overflow: 'hidden', minHeight: 0 }}
    >
      {/* Sidebar — hidden in welcome, visible in chat */}
      <Sidebar
        activeConversationId={conversationId}
        onSelectConversation={handleSelectConversation}
        onNewSession={handleNewSession}
        refreshKey={sidebarRefreshKey}
      />

      {/* Chat area */}
      <div className="work-chat">
        {/* Welcome screen — only in welcome stage */}
        {stage === 'welcome' && (
          <WelcomeScreen onSend={handleWelcomeSend} />
        )}

        {/* Chat column — only in chat stage */}
        {stage === 'chat' && (
          <div className="chat-col" style={{ display: 'flex' }}>
            <ChatPanel
              conversationId={conversationId}
              sessionKind={sessionKind}
              onConversationId={handleConversationId}
              onSessionClassified={handleSessionClassified}
              onNewChat={handleNewSession}
              initialMessage={initialMessage}
              onInitialMessageSent={handleInitialMessageSent}
            />
          </div>
        )}
      </div>
    </div>
  )
}
