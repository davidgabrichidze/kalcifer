import { useState, useEffect, useCallback, useRef } from 'react'
import {
  fetchConversations,
  renameConversation,
  archiveConversation,
  deleteConversation,
  type Conversation,
} from '../lib/api'

const KIND_META: Record<string, { icon: string; label: string }> = {
  campaign: { icon: '📣', label: 'კამპანიები' },
  flow: { icon: '⚡', label: 'ფლოუები' },
  analysis: { icon: '📊', label: 'ანალიზი' },
  debug: { icon: '🔍', label: 'დიაგნოსტიკა' },
}

interface SidebarProps {
  activeConversationId: string | null
  onSelectConversation: (id: string) => void
  onNewSession: () => void
  onConversationRemoved?: (id: string) => void
  refreshKey?: number
}

export default function Sidebar({
  activeConversationId,
  onSelectConversation,
  onNewSession,
  onConversationRemoved,
  refreshKey = 0,
}: SidebarProps) {
  const [conversations, setConversations] = useState<Conversation[]>([])
  const [loading, setLoading] = useState(false)
  const [contextMenu, setContextMenu] = useState<{
    conv: Conversation
    x: number
    y: number
  } | null>(null)
  const [editingId, setEditingId] = useState<string | null>(null)
  const [editValue, setEditValue] = useState('')
  const editRef = useRef<HTMLInputElement>(null)

  const loadConversations = useCallback(async () => {
    setLoading(true)
    try {
      const convs = await fetchConversations({ status: 'all' })
      setConversations(convs)
    } catch {
      // Silently fail
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    loadConversations()
  }, [loadConversations, refreshKey])

  // Focus edit input
  useEffect(() => {
    if (editingId) editRef.current?.focus()
  }, [editingId])

  // Close context menu on outside click
  useEffect(() => {
    if (!contextMenu) return
    const handler = () => setContextMenu(null)
    window.addEventListener('click', handler)
    return () => window.removeEventListener('click', handler)
  }, [contextMenu])

  // ── Actions ───────────────────────────────────

  async function handleRename(conv: Conversation) {
    setContextMenu(null)
    setEditingId(conv.id)
    setEditValue(conv.title || '')
  }

  async function commitRename(id: string) {
    const trimmed = editValue.trim()
    setEditingId(null)
    if (!trimmed) return
    try {
      await renameConversation(id, trimmed)
      loadConversations()
    } catch {
      // Ignore
    }
  }

  async function handleArchive(conv: Conversation) {
    setContextMenu(null)
    try {
      await archiveConversation(conv.id)
      loadConversations()
      onConversationRemoved?.(conv.id)
    } catch {
      // Ignore
    }
  }

  async function handleDelete(conv: Conversation) {
    setContextMenu(null)
    try {
      await deleteConversation(conv.id)
      loadConversations()
      onConversationRemoved?.(conv.id)
    } catch {
      // Ignore
    }
  }

  function handleContextMenu(e: React.MouseEvent, conv: Conversation) {
    e.preventDefault()
    e.stopPropagation()
    setContextMenu({ conv, x: e.clientX, y: e.clientY })
  }

  // ── Grouping ──────────────────────────────────

  const active = conversations.filter(c => c.status === 'active')
  const archived = conversations.filter(c => c.status === 'archived')

  // Group active by kind: unclassified first, then by kind
  const unclassified = active.filter(c => !c.kind)
  const grouped = new Map<string, Conversation[]>()
  for (const c of active) {
    if (!c.kind) continue
    const list = grouped.get(c.kind) ?? []
    list.push(c)
    grouped.set(c.kind, list)
  }

  // ── Render helpers ────────────────────────────

  function renderItem(c: Conversation, muted = false) {
    const isActive = c.id === activeConversationId
    const isEditing = c.id === editingId

    return (
      <div
        key={c.id}
        className={`flow-item${isActive ? ' active' : ''}`}
        onClick={() => !isEditing && onSelectConversation(c.id)}
        onContextMenu={e => handleContextMenu(e, c)}
        onDoubleClick={() => handleRename(c)}
      >
        <div className={`flow-dot ${getDotClass(c)}`} />
        <div style={{ flex: 1, minWidth: 0 }}>
          {isEditing ? (
            <input
              ref={editRef}
              value={editValue}
              onChange={e => setEditValue(e.target.value)}
              onBlur={() => commitRename(c.id)}
              onKeyDown={e => {
                if (e.key === 'Enter') commitRename(c.id)
                if (e.key === 'Escape') setEditingId(null)
              }}
              onClick={e => e.stopPropagation()}
              style={{
                width: '100%',
                fontSize: 12,
                fontWeight: 500,
                fontFamily: 'inherit',
                color: 'var(--color-text)',
                background: 'var(--color-surface-dim)',
                border: '1px solid var(--color-primary)',
                borderRadius: 4,
                padding: '2px 6px',
                outline: 'none',
              }}
            />
          ) : (
            <div
              style={{
                fontSize: 12,
                fontWeight: 500,
                color: muted ? 'var(--color-text-muted)' : 'var(--color-text)',
                whiteSpace: 'nowrap',
                overflow: 'hidden',
                textOverflow: 'ellipsis',
              }}
            >
              {c.title || 'ახალი საუბარი'}
            </div>
          )}
          <div style={{ fontSize: 10, color: 'var(--color-text-muted)', marginTop: 1 }}>
            {formatRelativeTime(c.updated_at)}
          </div>
        </div>
      </div>
    )
  }

  return (
    <div className="work-sidebar">
      <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
        {/* New session button */}
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
              marginBottom: 4,
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
        </div>

        {/* Scrollable session list */}
        <div
          className="sb-scroll"
          style={{ flex: 1, overflowY: 'auto', padding: '0 10px' }}
        >
          {loading && (
            <div style={{ padding: '8px', fontSize: 11, color: 'var(--color-text-muted)' }}>
              ...
            </div>
          )}

          {/* Unclassified conversations */}
          {unclassified.length > 0 && (
            <SectionLabel>ახალი საუბრები</SectionLabel>
          )}
          {unclassified.map(c => renderItem(c))}

          {/* Grouped by kind */}
          {Array.from(grouped.entries()).map(([kind, convs]) => (
            <div key={kind}>
              <SectionLabel>
                {KIND_META[kind]?.icon} {KIND_META[kind]?.label ?? kind}
              </SectionLabel>
              {convs.map(c => renderItem(c))}
            </div>
          ))}

          {active.length === 0 && !loading && (
            <div style={{ padding: '12px 8px', fontSize: 11, color: 'var(--color-text-muted)' }}>
              ჯერ საუბრები არ არის
            </div>
          )}

          {/* Archived */}
          {archived.length > 0 && (
            <>
              <SectionLabel>არქივი</SectionLabel>
              {archived.map(c => renderItem(c, true))}
            </>
          )}
        </div>
      </div>

      {/* Context menu */}
      {contextMenu && (
        <ContextMenu
          conv={contextMenu.conv}
          x={contextMenu.x}
          y={contextMenu.y}
          onRename={() => handleRename(contextMenu.conv)}
          onArchive={() => handleArchive(contextMenu.conv)}
          onDelete={() => handleDelete(contextMenu.conv)}
        />
      )}
    </div>
  )
}

// ── Sub-components ──────────────────────────────

function SectionLabel({ children }: { children: React.ReactNode }) {
  return (
    <div
      style={{
        fontSize: 10,
        fontWeight: 600,
        textTransform: 'uppercase',
        letterSpacing: 0.5,
        color: 'var(--color-text-muted)',
        padding: '8px 6px 3px',
      }}
    >
      {children}
    </div>
  )
}

function ContextMenu({
  conv,
  x,
  y,
  onRename,
  onArchive,
  onDelete,
}: {
  conv: Conversation
  x: number
  y: number
  onRename: () => void
  onArchive: () => void
  onDelete: () => void
}) {
  const isClassified = !!conv.kind
  const isArchived = conv.status === 'archived'

  return (
    <div
      style={{
        position: 'fixed',
        top: y,
        left: x,
        zIndex: 1000,
        background: 'var(--color-surface)',
        border: '1px solid var(--color-border)',
        borderRadius: 8,
        padding: 4,
        boxShadow: 'var(--shadow-md)',
        minWidth: 140,
      }}
      onClick={e => e.stopPropagation()}
    >
      <ContextMenuItem onClick={onRename}>
        სახელის შეცვლა
      </ContextMenuItem>

      {!isArchived && isClassified && (
        <ContextMenuItem onClick={onArchive}>
          არქივში გადატანა
        </ContextMenuItem>
      )}

      {!isClassified && (
        <ContextMenuItem onClick={onDelete} danger>
          წაშლა
        </ContextMenuItem>
      )}

      {isArchived && (
        <ContextMenuItem onClick={onDelete} danger>
          წაშლა
        </ContextMenuItem>
      )}
    </div>
  )
}

function ContextMenuItem({
  children,
  onClick,
  danger = false,
}: {
  children: React.ReactNode
  onClick: () => void
  danger?: boolean
}) {
  return (
    <button
      onClick={onClick}
      style={{
        display: 'block',
        width: '100%',
        textAlign: 'left',
        padding: '6px 10px',
        background: 'none',
        border: 'none',
        borderRadius: 5,
        fontSize: 11.5,
        fontFamily: 'inherit',
        color: danger ? 'var(--color-danger)' : 'var(--color-text)',
        cursor: 'pointer',
        transition: 'background 0.1s',
      }}
      onMouseEnter={e => {
        e.currentTarget.style.background = danger
          ? 'var(--color-danger-soft)'
          : 'var(--color-surface-dim)'
      }}
      onMouseLeave={e => {
        e.currentTarget.style.background = 'none'
      }}
    >
      {children}
    </button>
  )
}

// ── Utilities ───────────────────────────────────

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
