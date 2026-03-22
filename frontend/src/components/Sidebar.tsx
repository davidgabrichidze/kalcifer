import { useState, useEffect, useCallback } from 'react'
import { fetchConversations, type Conversation } from '../lib/api'

const KIND_ICONS: Record<string, string> = {
  campaign: '📣',
  flow: '⚡',
  analysis: '📊',
  debug: '🔍',
}

interface SidebarProps {
  activeConversationId: string | null
  onSelectConversation: (id: string) => void
  onNewSession: () => void
  /** Increment to force refresh */
  refreshKey?: number
}

export default function Sidebar({
  activeConversationId,
  onSelectConversation,
  onNewSession,
  refreshKey = 0,
}: SidebarProps) {
  const [conversations, setConversations] = useState<Conversation[]>([])
  const [loading, setLoading] = useState(false)

  const loadConversations = useCallback(async () => {
    setLoading(true)
    try {
      const convs = await fetchConversations()
      setConversations(convs)
    } catch {
      // Silently fail — sidebar is non-critical
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    loadConversations()
  }, [loadConversations, refreshKey])

  const active = conversations.filter(c => c.status === 'active')
  const archived = conversations.filter(c => c.status === 'archived')

  function formatMeta(c: Conversation): string {
    const kind = c.kind ? (KIND_ICONS[c.kind] ?? '') + ' ' : ''
    const time = formatRelativeTime(c.updated_at)
    return `${kind}${time}`
  }

  return (
    <div className="work-sidebar">
      <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
        {/* New session button + label */}
        <div style={{ padding: '10px 10px 4px' }}>
          <button
            onClick={onNewSession}
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: 6,
              width: '100%',
              padding: '7px 10px',
              background: 'var(--color-primary-soft)',
              border: '1px dashed var(--color-primary)',
              borderRadius: 10,
              color: 'var(--color-primary)',
              fontSize: 12,
              fontWeight: 500,
              cursor: 'pointer',
              fontFamily: 'inherit',
              transition: 'all 0.2s',
              marginBottom: 6,
            }}
            onMouseEnter={e => {
              const el = e.currentTarget
              el.style.background = 'var(--color-primary)'
              el.style.color = 'var(--color-text-on-primary)'
              el.style.borderStyle = 'solid'
            }}
            onMouseLeave={e => {
              const el = e.currentTarget
              el.style.background = 'var(--color-primary-soft)'
              el.style.color = 'var(--color-primary)'
              el.style.borderStyle = 'dashed'
            }}
          >
            + ახალი სესია
          </button>
          <div
            style={{
              fontSize: 10,
              fontWeight: 600,
              textTransform: 'uppercase',
              letterSpacing: 0.5,
              color: 'var(--color-text-muted)',
              padding: '0 6px',
              marginBottom: 4,
            }}
          >
            {loading ? '...' : 'Active Sessions'}
          </div>
        </div>

        {/* Scrollable session list */}
        <div
          className="sb-scroll"
          style={{ flex: 1, overflowY: 'auto', padding: '0 10px' }}
        >
          {active.map(c => (
            <div
              key={c.id}
              className={`flow-item${c.id === activeConversationId ? ' active' : ''}`}
              onClick={() => onSelectConversation(c.id)}
            >
              <div className={`flow-dot ${getDotClass(c)}`} />
              <div style={{ flex: 1, minWidth: 0 }}>
                <div
                  style={{
                    fontSize: 12,
                    fontWeight: 500,
                    color: 'var(--color-text)',
                    whiteSpace: 'nowrap',
                    overflow: 'hidden',
                    textOverflow: 'ellipsis',
                  }}
                >
                  {c.title || 'ახალი საუბარი'}
                </div>
                <div style={{ fontSize: 10, color: 'var(--color-text-muted)', marginTop: 1 }}>
                  {formatMeta(c)}
                </div>
              </div>
            </div>
          ))}

          {active.length === 0 && !loading && (
            <div style={{ padding: '12px 8px', fontSize: 11, color: 'var(--color-text-muted)' }}>
              ჯერ საუბრები არ არის
            </div>
          )}

          {/* Archived section */}
          {archived.length > 0 && (
            <>
              <div style={{ padding: '8px 6px 4px' }}>
                <div
                  style={{
                    fontSize: 10,
                    fontWeight: 600,
                    textTransform: 'uppercase',
                    letterSpacing: 0.5,
                    color: 'var(--color-text-muted)',
                    padding: '0 6px',
                    marginBottom: 4,
                  }}
                >
                  Archived
                </div>
              </div>
              {archived.map(c => (
                <div
                  key={c.id}
                  className={`flow-item${c.id === activeConversationId ? ' active' : ''}`}
                  onClick={() => onSelectConversation(c.id)}
                >
                  <div className="flow-dot dot-archived" />
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div
                      style={{
                        fontSize: 12,
                        fontWeight: 500,
                        color: 'var(--color-text-muted)',
                        whiteSpace: 'nowrap',
                        overflow: 'hidden',
                        textOverflow: 'ellipsis',
                      }}
                    >
                      {c.title || 'არქივი'}
                    </div>
                    <div style={{ fontSize: 10, color: 'var(--color-text-muted)', marginTop: 1 }}>
                      {formatMeta(c)}
                    </div>
                  </div>
                </div>
              ))}
            </>
          )}
        </div>
      </div>
    </div>
  )
}

function getDotClass(c: Conversation): string {
  if (c.status === 'archived') return 'dot-archived'
  if (c.kind) return 'dot-active'
  return 'dot-draft'
}

function formatRelativeTime(isoDate: string): string {
  try {
    const diff = Date.now() - new Date(isoDate).getTime()
    const mins = Math.floor(diff / 60_000)
    if (mins < 1) return 'ახლახანს'
    if (mins < 60) return `${mins} წთ წინ`
    const hours = Math.floor(mins / 60)
    if (hours < 24) return `${hours} სთ წინ`
    const days = Math.floor(hours / 24)
    if (days < 7) return `${days} დღის წინ`
    return new Date(isoDate).toLocaleDateString('ka-GE', { day: 'numeric', month: 'short' })
  } catch {
    return ''
  }
}
