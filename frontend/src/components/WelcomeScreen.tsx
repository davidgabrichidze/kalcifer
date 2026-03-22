import { useState, useRef, useEffect } from 'react'

const HINTS = [
  { label: 'Churn re-engagement', text: '90 დღე არააქტიურ მომხმარებლებს email და SMS გავუგზავნო' },
  { label: 'Onboarding flow', text: 'ახალ მომხმარებლებს onboarding flow გავუკეთო' },
  { label: 'A/B ტესტი', text: 'A/B ტესტი email subject-ებისთვის' },
  { label: 'რა nodes არსებობს?', text: 'რა nodes არსებობს?' },
]

interface WelcomeScreenProps {
  onSend: (text: string) => void
}

export default function WelcomeScreen({ onSend }: WelcomeScreenProps) {
  const [input, setInput] = useState('')
  const [exiting, setExiting] = useState(false)
  const textareaRef = useRef<HTMLTextAreaElement>(null)

  // Auto-resize textarea
  useEffect(() => {
    const el = textareaRef.current
    if (el) {
      el.style.height = 'auto'
      el.style.height = `${Math.min(el.scrollHeight, 80)}px`
    }
  }, [input])

  function doSend(text: string) {
    const trimmed = text.trim()
    if (!trimmed || exiting) return

    setExiting(true)
    // Animate out, then send
    setTimeout(() => {
      onSend(trimmed)
    }, 450)
  }

  function handleKeyDown(e: React.KeyboardEvent) {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      doSend(input)
    }
  }

  return (
    <div className={`welcome-center${exiting ? ' exiting' : ''}`}>
      {/* Breathing avatar */}
      <div
        className="welcome-avatar"
        style={{
          width: 80,
          height: 80,
          borderRadius: '50%',
          background: 'var(--color-primary-soft)',
          border: '2px solid var(--color-primary)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          fontSize: 32,
          fontWeight: 700,
          color: 'var(--color-primary)',
          marginBottom: 20,
          animation: 'breathe 4s ease-in-out infinite',
        }}
      >
        K
      </div>

      {/* Title */}
      <div
        className="welcome-title"
        style={{
          fontSize: 22,
          fontWeight: 600,
          color: 'var(--color-text)',
          marginBottom: 6,
        }}
      >
        რაზე ვიმუშაოთ?
      </div>

      {/* Subtitle */}
      <div
        className="welcome-sub"
        style={{
          fontSize: 13,
          color: 'var(--color-text-muted)',
          maxWidth: 360,
          lineHeight: 1.6,
          marginBottom: 24,
        }}
      >
        მიამბე რა გინდა გააკეთო — flow-ს ავაწყობ, გავტესტავ, გავაანალიზებ.
        ან აირჩიე მარცხნიდან არსებული flow.
      </div>

      {/* Hint buttons */}
      <div
        className="welcome-hints"
        style={{
          display: 'flex',
          flexWrap: 'wrap',
          gap: 6,
          justifyContent: 'center',
          maxWidth: 440,
        }}
      >
        {HINTS.map(h => (
          <button
            key={h.label}
            onClick={() => doSend(h.text)}
            style={{
              background: 'var(--color-surface)',
              border: '1px solid var(--color-border)',
              color: 'var(--color-text-sec)',
              padding: '6px 14px',
              borderRadius: 20,
              fontSize: 11.5,
              cursor: 'pointer',
              fontFamily: 'inherit',
              transition: 'all 0.2s',
            }}
            onMouseEnter={e => {
              const el = e.currentTarget
              el.style.borderColor = 'var(--color-primary)'
              el.style.color = 'var(--color-primary)'
              el.style.background = 'var(--color-primary-soft)'
            }}
            onMouseLeave={e => {
              const el = e.currentTarget
              el.style.borderColor = 'var(--color-border)'
              el.style.color = 'var(--color-text-sec)'
              el.style.background = 'var(--color-surface)'
            }}
          >
            {h.label}
          </button>
        ))}
      </div>

      {/* Input area */}
      <div className="welcome-input-area" style={{ width: '100%', maxWidth: 520, marginTop: 16 }}>
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
            placeholder="მიამბე რა გინდა გააკეთო..."
            rows={1}
            style={{
              flex: 1,
              background: 'none',
              border: 'none',
              color: 'var(--color-text)',
              fontSize: 13,
              fontFamily: 'inherit',
              resize: 'none',
              outline: 'none',
              maxHeight: 80,
              lineHeight: 1.5,
            }}
          />
          <button
            onClick={() => doSend(input)}
            disabled={!input.trim()}
            style={{
              background: input.trim() ? 'var(--color-primary)' : 'var(--color-surface-dim)',
              border: 'none',
              color: input.trim() ? 'var(--color-text-on-primary)' : 'var(--color-text-muted)',
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
