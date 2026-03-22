import { useState, useRef, useEffect, useCallback } from 'react'
import Markdown from 'react-markdown'
import { type ChatMessage, createMessage } from '../lib/chat'
import { streamChat, type ApiMessage } from '../lib/api'

interface ChatPanelProps {
  placeholder?: string
}

export default function ChatPanel({
  placeholder = 'მიამბე რა გინდა გააკეთო...',
}: ChatPanelProps) {
  const [messages, setMessages] = useState<ChatMessage[]>([])
  const [input, setInput] = useState('')
  const [isTyping, setIsTyping] = useState(false)
  const [_streamingId, setStreamingId] = useState<string | null>(null)
  const msgsEndRef = useRef<HTMLDivElement>(null)
  const textareaRef = useRef<HTMLTextAreaElement>(null)
  const abortRef = useRef<AbortController | null>(null)

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

  // Append text to a streaming AI message
  const appendToMessage = useCallback((id: string, text: string) => {
    setMessages(prev =>
      prev.map(m => (m.id === id ? { ...m, content: m.content + text } : m)),
    )
  }, [])

  function handleSend() {
    const text = input.trim()
    if (!text || isTyping) return

    const userMsg = createMessage('user', text)
    const aiMsg = createMessage('ai', '')
    setMessages(prev => [...prev, userMsg, aiMsg])
    setInput('')
    setIsTyping(true)
    setStreamingId(aiMsg.id)

    // Build API messages from history
    const apiMessages: ApiMessage[] = [
      ...messages.map(m => ({
        role: (m.role === 'ai' ? 'assistant' : 'user') as ApiMessage['role'],
        content: m.content,
      })),
      { role: 'user', content: text },
    ]

    abortRef.current = streamChat(apiMessages, {
      onDelta: (chunk) => appendToMessage(aiMsg.id, chunk),
      onDone: () => {
        setIsTyping(false)
        setStreamingId(null)
      },
      onError: (msg) => {
        appendToMessage(aiMsg.id, `\n\n⚠ ${msg}`)
        setIsTyping(false)
        setStreamingId(null)
      },
    })
  }

  function handleKeyDown(e: React.KeyboardEvent) {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      handleSend()
    }
  }

  const hasMessages = messages.length > 0

  return (
    <div
      className="flex flex-col"
      style={{ height: '100%', minHeight: 0, background: 'var(--color-bg)' }}
    >
      {/* Messages */}
      <div
        className="flex-1 overflow-y-auto"
        style={{
          padding: hasMessages ? '16px' : 0,
          display: hasMessages ? 'block' : 'flex',
          alignItems: 'center',
          justifyContent: 'center',
        }}
      >
        {!hasMessages && (
          <div style={{ textAlign: 'center', padding: 40 }}>
            <div style={{ fontSize: 40, marginBottom: 8 }}>🔥</div>
            <div
              style={{
                fontSize: 20,
                fontWeight: 700,
                color: 'var(--color-primary)',
                letterSpacing: '-0.5px',
                marginBottom: 6,
              }}
            >
              Kalcifer
            </div>
            <div
              style={{
                fontSize: 14,
                color: 'var(--color-text-muted)',
              }}
            >
              სახლის გული ცოცხალია
            </div>
          </div>
        )}

        {messages.map(msg => {
          const isUser = msg.role === 'user'

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
              <div
                className="chat-md"
                style={{
                  padding: '12px 16px',
                  borderRadius: 14,
                  fontSize: 14.5,
                  lineHeight: 1.65,
                  maxWidth: '85%',
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
            </div>
          )
        })}

        {/* Typing indicator */}
        {isTyping && (
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
                width: 26,
                height: 26,
                borderRadius: '50%',
                flexShrink: 0,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                fontSize: 10,
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
