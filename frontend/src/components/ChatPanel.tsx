import { useState, useRef, useEffect, useCallback } from 'react'
import Markdown from 'react-markdown'
import { type ChatMessage, type ToolActivity, createMessage } from '../lib/chat'
import { streamChat, fetchConversation, type ApiMessage, type SessionClassification } from '../lib/api'

// Human-readable names for tools
const TOOL_LABELS: Record<string, string> = {
  classify_session: 'სესიის კლასიფიკაცია',
  list_flows: 'ფლოუების ჩამონათვალი',
  get_flow: 'ფლოუს დეტალები',
  create_flow: 'ფლოუს შექმნა',
  list_node_types: 'ნაბიჯების ტიპები',
  remember: 'დამახსოვრება',
  recall: 'გახსენება',
}

const KIND_LABELS: Record<string, { label: string; icon: string }> = {
  campaign: { label: 'კამპანია', icon: '📣' },
  flow: { label: 'ფლოუ', icon: '⚡' },
  analysis: { label: 'ანალიზი', icon: '📊' },
  debug: { label: 'დიაგნოსტიკა', icon: '🔍' },
}

interface ChatPanelProps {
  placeholder?: string
  conversationId: string | null
  sessionKind: SessionClassification | null
  onConversationId?: (id: string) => void
  onSessionClassified?: (classification: SessionClassification) => void
  onNewChat?: () => void
  /** If set, send this text immediately on mount (used by welcome screen) */
  initialMessage?: string | null
  onInitialMessageSent?: () => void
}

export default function ChatPanel({
  placeholder = 'მიამბე რა გინდა გააკეთო...',
  conversationId,
  sessionKind,
  onConversationId,
  onSessionClassified,
  onNewChat,
  initialMessage,
  onInitialMessageSent,
}: ChatPanelProps) {
  const [messages, setMessages] = useState<ChatMessage[]>([])
  const [input, setInput] = useState('')
  const [isTyping, setIsTyping] = useState(false)
  const [_streamingId, setStreamingId] = useState<string | null>(null)
  const msgsEndRef = useRef<HTMLDivElement>(null)
  const textareaRef = useRef<HTMLTextAreaElement>(null)
  const abortRef = useRef<AbortController | null>(null)
  const activeAiIdRef = useRef<string | null>(null)
  const initialMessageSentRef = useRef(false)

  // Auto-scroll to bottom
  useEffect(() => {
    msgsEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages, isTyping])

  // Auto-resize textarea
  useEffect(() => {
    const el = textareaRef.current
    if (el) {
      el.style.height = 'auto'
      el.style.height = `${Math.min(el.scrollHeight, 80)}px`
    }
  }, [input])

  const appendToMessage = useCallback((id: string, text: string) => {
    setMessages(prev =>
      prev.map(m => (m.id === id ? { ...m, content: m.content + text } : m)),
    )
  }, [])

  const addToolToMessage = useCallback((id: string, tool: ToolActivity) => {
    setMessages(prev =>
      prev.map(m => {
        if (m.id !== id) return m
        const existing = m.tools ?? []
        // Update if same tool already exists (running → done)
        const idx = existing.findIndex(t => t.tool === tool.tool && t.status === 'running')
        if (idx >= 0 && tool.status === 'done') {
          const updated = [...existing]
          updated[idx] = tool
          return { ...m, tools: updated }
        }
        return { ...m, tools: [...existing, tool] }
      }),
    )
  }, [])

  function handleSend() {
    const text = input.trim()
    if (!text || isTyping) return

    const userMsg = createMessage('user', text)
    const aiMsg = createMessage('ai', '')
    activeAiIdRef.current = aiMsg.id
    setMessages(prev => [...prev, userMsg, aiMsg])
    setInput('')
    setIsTyping(true)
    setStreamingId(aiMsg.id)

    // Only send the new user message — backend loads history from conversation
    const apiMessages: ApiMessage[] = [{ role: 'user', content: text }]

    abortRef.current = streamChat(
      apiMessages,
      {
        onInit: (convId) => onConversationId?.(convId),
        onSessionClassified: (classification) => onSessionClassified?.(classification),
        onDelta: (chunk) => appendToMessage(aiMsg.id, chunk),
        onToolStart: (tool) => {
          addToolToMessage(aiMsg.id, { tool, status: 'running' })
        },
        onToolDone: (tool, result) => {
          addToolToMessage(aiMsg.id, { tool, status: 'done', result })
        },
        onDone: () => {
          setIsTyping(false)
          setStreamingId(null)
          activeAiIdRef.current = null
        },
        onError: (msg) => {
          appendToMessage(aiMsg.id, `\n\n⚠ ${msg}`)
          setIsTyping(false)
          setStreamingId(null)
          activeAiIdRef.current = null
        },
      },
      conversationId ?? undefined,
    )
  }

  function handleKeyDown(e: React.KeyboardEvent) {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      handleSend()
    }
  }

  function handleNewChat() {
    if (isTyping) return
    abortRef.current?.abort()
    setMessages([])
    setInput('')
    onNewChat?.()
  }

  // Send initial message from welcome screen (ref guard prevents StrictMode double-fire)
  useEffect(() => {
    if (initialMessage && !isTyping && messages.length === 0 && !initialMessageSentRef.current) {
      initialMessageSentRef.current = true
      const text = initialMessage
      onInitialMessageSent?.()

      const userMsg = createMessage('user', text)
      const aiMsg = createMessage('ai', '')
      activeAiIdRef.current = aiMsg.id
      setMessages([userMsg, aiMsg])
      setIsTyping(true)
      setStreamingId(aiMsg.id)

      const apiMessages: ApiMessage[] = [{ role: 'user', content: text }]
      abortRef.current = streamChat(
        apiMessages,
        {
          onInit: (convId) => onConversationId?.(convId),
          onSessionClassified: (classification) => onSessionClassified?.(classification),
          onDelta: (chunk) => appendToMessage(aiMsg.id, chunk),
          onToolStart: (tool) => {
            addToolToMessage(aiMsg.id, { tool, status: 'running' })
          },
          onToolDone: (tool, result) => {
            addToolToMessage(aiMsg.id, { tool, status: 'done', result })
          },
          onDone: () => {
            setIsTyping(false)
            setStreamingId(null)
            activeAiIdRef.current = null
          },
          onError: (msg) => {
            appendToMessage(aiMsg.id, `\n\n⚠ ${msg}`)
            setIsTyping(false)
            setStreamingId(null)
            activeAiIdRef.current = null
          },
        },
        conversationId ?? undefined,
      )
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [initialMessage])

  // Load conversation history when switching via sidebar
  const loadedConvRef = useRef<string | null>(null)
  useEffect(() => {
    if (!conversationId || conversationId === loadedConvRef.current) return
    if (initialMessage) return // Skip if we're sending initial message
    loadedConvRef.current = conversationId

    async function loadHistory() {
      try {
        const detail = await fetchConversation(conversationId!)
        const loaded: ChatMessage[] = detail.messages.map(m =>
          createMessage(m.role === 'user' ? 'user' : 'ai', m.content),
        )
        setMessages(loaded)
      } catch {
        // Ignore — conversation might not exist yet
      }
    }
    loadHistory()
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [conversationId])

  // Reset state when conversation is cleared (but not during initial message send)
  useEffect(() => {
    if (!conversationId && !initialMessage) {
      loadedConvRef.current = null
      initialMessageSentRef.current = false
      setMessages([])
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [conversationId])

  const hasMessages = messages.length > 0

  return (
    <div
      className="flex flex-col"
      style={{ height: '100%', minHeight: 0, background: 'var(--color-bg)' }}
    >
      {/* Header with session kind badge + new chat button */}
      {hasMessages && (
        <div
          style={{
            display: 'flex',
            justifyContent: 'space-between',
            alignItems: 'center',
            padding: '8px 16px 0',
            flexShrink: 0,
          }}
        >
          {/* Session kind badge */}
          {sessionKind ? (
            <div
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: 6,
                fontSize: 12.5,
                fontWeight: 600,
                color: 'var(--color-text)',
              }}
            >
              <span>{KIND_LABELS[sessionKind.kind]?.icon}</span>
              <span>{sessionKind.title}</span>
              <span
                style={{
                  fontSize: 10,
                  padding: '2px 6px',
                  borderRadius: 6,
                  background: 'var(--color-primary-soft)',
                  color: 'var(--color-primary)',
                }}
              >
                {KIND_LABELS[sessionKind.kind]?.label}
              </span>
            </div>
          ) : (
            <div />
          )}

          <button
            onClick={handleNewChat}
            disabled={isTyping}
            style={{
              background: 'none',
              border: '1px solid var(--color-border)',
              color: 'var(--color-text-muted)',
              fontSize: 12,
              padding: '4px 10px',
              borderRadius: 8,
              cursor: isTyping ? 'default' : 'pointer',
              opacity: isTyping ? 0.4 : 1,
              transition: 'all 0.2s',
              flexShrink: 0,
            }}
          >
            + ახალი საუბარი
          </button>
        </div>
      )}

      {/* Messages */}
      <div
        className="flex-1 overflow-y-auto"
        style={{ padding: '16px' }}
      >
        {messages.map(msg => {
          const isUser = msg.role === 'user'
          const hasContent = msg.content.length > 0
          const hasTools = (msg.tools?.length ?? 0) > 0

          // Hide empty AI messages (typing indicator handles the visual)
          if (!isUser && !hasContent && !hasTools) return null

          return (
            <div
              key={msg.id}
              style={{
                display: 'flex',
                gap: 8,
                marginBottom: 12,
                alignItems: 'flex-start',
                flexDirection: isUser ? 'row-reverse' : 'row',
              }}
            >
              {/* Avatar */}
              <div
                style={{
                  width: 30,
                  height: 30,
                  borderRadius: '50%',
                  flexShrink: 0,
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  fontSize: 11,
                  fontWeight: 600,
                  background: isUser
                    ? 'var(--color-accent)'
                    : 'var(--color-primary)',
                  color: 'var(--color-text-on-primary)',
                }}
              >
                {isUser ? 'DG' : 'K'}
              </div>

              {/* Body */}
              <div style={{ maxWidth: '85%' }}>
                {/* Tool activity indicators */}
                {msg.tools && msg.tools.length > 0 && (
                  <div style={{ marginBottom: 6 }}>
                    {msg.tools.map((t, i) => (
                      <div
                        key={i}
                        style={{
                          display: 'inline-flex',
                          alignItems: 'center',
                          gap: 6,
                          padding: '4px 10px',
                          marginRight: 4,
                          marginBottom: 4,
                          borderRadius: 8,
                          fontSize: 12,
                          background: 'var(--color-info-soft)',
                          color: 'var(--color-info)',
                          border: '1px solid var(--color-info-soft)',
                        }}
                      >
                        <span style={{
                          width: 6,
                          height: 6,
                          borderRadius: '50%',
                          background: t.status === 'running'
                            ? 'var(--color-warn)'
                            : 'var(--color-success)',
                          animation: t.status === 'running'
                            ? 'typingDot 1.2s infinite'
                            : 'none',
                        }} />
                        {TOOL_LABELS[t.tool] ?? t.tool}
                        {t.status === 'done' && ' ✓'}
                      </div>
                    ))}
                  </div>
                )}

                {/* Message bubble */}
                {(msg.content || isUser) && (
                  <div
                    className="chat-md"
                    style={{
                      padding: '12px 16px',
                      borderRadius: 14,
                      fontSize: 14.5,
                      lineHeight: 1.65,
                      ...(isUser
                        ? {
                            background: 'var(--color-primary-soft)',
                            border: '1px solid var(--color-primary-muted)',
                            color: 'var(--color-text)',
                          }
                        : {
                            background: 'var(--color-surface)',
                            border: '1px solid var(--color-border)',
                            color: 'var(--color-text)',
                          }),
                    }}
                  >
                    {isUser ? (
                      msg.content
                    ) : (
                      <Markdown>{msg.content}</Markdown>
                    )}
                  </div>
                )}
              </div>
            </div>
          )
        })}

        {/* Typing indicator — shown while waiting, hidden once content or tools arrive */}
        {isTyping && !messages.some(m => m.id === activeAiIdRef.current && (m.content.length > 0 || (m.tools?.length ?? 0) > 0)) && (
          <div
            style={{
              display: 'flex',
              gap: 8,
              marginBottom: 12,
              alignItems: 'flex-start',
            }}
          >
            <div
              style={{
                width: 30,
                height: 30,
                borderRadius: '50%',
                flexShrink: 0,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                fontSize: 11,
                fontWeight: 600,
                background: 'var(--color-primary)',
                color: 'var(--color-text-on-primary)',
              }}
            >
              K
            </div>
            <div
              style={{
                padding: '10px 14px',
                borderRadius: 14,
                background: 'var(--color-surface)',
                border: '1px solid var(--color-border)',
              }}
            >
              <div
                data-testid="typing-indicator"
                style={{ display: 'flex', gap: 3, padding: '3px 0' }}
              >
                <span
                  style={{
                    width: 5,
                    height: 5,
                    borderRadius: '50%',
                    background: 'var(--color-primary)',
                    animation: 'typingDot 1.2s infinite',
                  }}
                />
                <span
                  style={{
                    width: 5,
                    height: 5,
                    borderRadius: '50%',
                    background: 'var(--color-primary)',
                    animation: 'typingDot 1.2s infinite 0.2s',
                  }}
                />
                <span
                  style={{
                    width: 5,
                    height: 5,
                    borderRadius: '50%',
                    background: 'var(--color-primary)',
                    animation: 'typingDot 1.2s infinite 0.4s',
                  }}
                />
              </div>
            </div>
          </div>
        )}

        <div ref={msgsEndRef} />
      </div>

      {/* Input */}
      <div
        style={{
          padding: '10px 16px 12px',
          flexShrink: 0,
          borderTop: hasMessages ? '1px solid var(--color-border)' : 'none',
        }}
      >
        <div
          style={{
            display: 'flex',
            alignItems: 'flex-end',
            gap: 6,
            background: 'var(--color-surface)',
            border: '1.5px solid var(--color-border)',
            borderRadius: 14,
            padding: '8px 12px',
            transition: 'all 0.2s',
          }}
        >
          <textarea
            ref={textareaRef}
            value={input}
            onChange={e => setInput(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder={placeholder}
            rows={1}
            style={{
              flex: 1,
              background: 'none',
              border: 'none',
              color: 'var(--color-text)',
              fontSize: 14.5,
              fontFamily: 'inherit',
              resize: 'none',
              outline: 'none',
              maxHeight: 80,
              lineHeight: 1.5,
            }}
          />
          <button
            onClick={handleSend}
            disabled={!input.trim()}
            title="Send"
            style={{
              background: input.trim()
                ? 'var(--color-primary)'
                : 'var(--color-surface-dim)',
              border: 'none',
              color: input.trim()
                ? 'var(--color-text-on-primary)'
                : 'var(--color-text-muted)',
              width: 30,
              height: 30,
              borderRadius: '50%',
              cursor: input.trim() ? 'pointer' : 'default',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              transition: 'all 0.2s',
              flexShrink: 0,
            }}
          >
            <svg
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth={2.5}
              strokeLinecap="round"
              strokeLinejoin="round"
              style={{ width: 13, height: 13 }}
            >
              <line x1="22" y1="2" x2="11" y2="13" />
              <polygon points="22 2 15 22 11 13 2 9 22 2" />
            </svg>
          </button>
        </div>
      </div>
    </div>
  )
}
