import { useEffect, useRef } from 'react'

interface ChatInputProps {
  value: string
  onChange: (value: string) => void
  onSend: () => void
  placeholder?: string
  disabled?: boolean
}

export default function ChatInput({
  value,
  onChange,
  onSend,
  placeholder = 'მიამბე რა გინდა გააკეთო...',
  disabled = false,
}: ChatInputProps) {
  const textareaRef = useRef<HTMLTextAreaElement>(null)

  // Auto-resize textarea
  useEffect(() => {
    const el = textareaRef.current
    if (el) {
      el.style.height = 'auto'
      el.style.height = `${Math.min(el.scrollHeight, 100)}px`
    }
  }, [value])

  function handleKeyDown(e: React.KeyboardEvent) {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      if (value.trim() && !disabled) onSend()
    }
  }

  const hasText = value.trim().length > 0

  return (
    <div style={{ padding: '10px 16px 14px', flexShrink: 0 }}>
      <div
        className="input-glow"
        style={{
          display: 'flex',
          alignItems: 'flex-end',
          gap: 8,
          background: 'var(--color-surface)',
          border: '1.5px solid var(--color-border)',
          borderRadius: 16,
          padding: '10px 14px',
          transition: 'border-color 0.2s, box-shadow 0.2s',
        }}
      >
        {/* Attach button */}
        <button
          title="ფაილის მიმაგრება"
          tabIndex={-1}
          style={{
            width: 32,
            height: 32,
            borderRadius: 8,
            background: 'var(--color-surface-dim)',
            border: '1px solid var(--color-border)',
            color: 'var(--color-text-muted)',
            cursor: 'pointer',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            fontSize: 15,
            flexShrink: 0,
          }}
        >
          📎
        </button>

        <textarea
          ref={textareaRef}
          value={value}
          onChange={e => onChange(e.target.value)}
          onKeyDown={handleKeyDown}
          placeholder={placeholder}
          rows={1}
          disabled={disabled}
          style={{
            flex: 1,
            background: 'none',
            border: 'none',
            color: 'var(--color-text)',
            fontSize: 14,
            fontFamily: 'inherit',
            resize: 'none',
            outline: 'none',
            maxHeight: 100,
            lineHeight: 1.5,
            padding: '4px 0',
          }}
        />

        <button
          onClick={onSend}
          disabled={!hasText || disabled}
          title="გაგზავნა"
          style={{
            background: hasText && !disabled
              ? 'var(--color-primary)'
              : 'var(--color-surface-dim)',
            border: 'none',
            color: hasText && !disabled
              ? 'var(--color-text-on-primary)'
              : 'var(--color-text-muted)',
            width: 34,
            height: 34,
            borderRadius: 10,
            cursor: hasText && !disabled ? 'pointer' : 'default',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            flexShrink: 0,
            transition: 'background 0.15s, color 0.15s',
          }}
        >
          <svg
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth={2.5}
            strokeLinecap="round"
            strokeLinejoin="round"
            style={{ width: 14, height: 14 }}
          >
            <line x1="22" y1="2" x2="11" y2="13" />
            <polygon points="22 2 15 22 11 13 2 9 22 2" />
          </svg>
        </button>
      </div>

      {/* Keyboard hints */}
      <div style={{
        display: 'flex',
        justifyContent: 'center',
        padding: '5px 0 0',
        fontSize: 10,
        color: 'var(--color-text-muted)',
        gap: 8,
      }}>
        <span>Enter გასაგზავნად</span>
        <span>·</span>
        <span>Shift+Enter ახალი ხაზი</span>
      </div>
    </div>
  )
}
