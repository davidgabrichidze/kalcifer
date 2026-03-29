import { useState } from 'react'
import { type ToolActivity } from '../lib/chat'
import { type Artifact } from './ArtifactPanel'
import CollapsibleSection from './CollapsibleSection'

interface ContextItem {
  tag: 'SKILL' | 'META'
  label: string
  detail?: string
}

interface RightSidebarProps {
  progressSteps: ToolActivity[]
  artifacts: Artifact[]
  contextItems: ContextItem[]
  onArtifactClick: (artifact: Artifact) => void
  isWorking?: boolean
}

export type { ContextItem }

const TYPE_META: Record<string, { icon: string; color: string }> = {
  flow: { icon: '⚡', color: 'var(--color-primary)' },
  analysis: { icon: '📊', color: 'var(--color-info)' },
  memory: { icon: '🧠', color: 'var(--color-accent)' },
  debug: { icon: '🔍', color: 'var(--color-warn)' },
  graph: { icon: '🔀', color: 'var(--color-success)' },
}

export default function RightSidebar({
  progressSteps,
  artifacts,
  contextItems,
  onArtifactClick,
  isWorking = false,
}: RightSidebarProps) {
  const [progressExpanded, setProgressExpanded] = useState(true)
  const [artifactsExpanded, setArtifactsExpanded] = useState(true)
  const [contextExpanded, setContextExpanded] = useState(false)

  const doneCount = progressSteps.filter(s => s.status === 'done').length
  const progressHeader = isWorking
    ? 'მიმდინარეობს...'
    : `${doneCount}/${progressSteps.length} შესრულდა`

  return (
    <div className="right-panel-scroll">
      {/* Progress / Todo */}
      {progressSteps.length > 0 && (
        <CollapsibleSection
          title={progressHeader}
          icon="●"
          expanded={progressExpanded}
          onToggle={() => setProgressExpanded(e => !e)}
        >
          {progressSteps.map((step, i) => (
            <div
              key={i}
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: 6,
                padding: '3px 0',
                fontSize: 11.5,
                color: 'var(--color-text-sec)',
              }}
            >
              <span
                style={{
                  width: 6,
                  height: 6,
                  borderRadius: '50%',
                  flexShrink: 0,
                  background: step.status === 'done'
                    ? 'var(--color-success)'
                    : 'var(--color-warn)',
                  animation: step.status === 'running'
                    ? 'typingDot 1.2s infinite'
                    : 'none',
                }}
              />
              {step.tool}
              {step.status === 'done' && (
                <span style={{ color: 'var(--color-success)', fontSize: 10 }}>✓</span>
              )}
            </div>
          ))}
        </CollapsibleSection>
      )}

      {/* Artifacts */}
      <CollapsibleSection
        title={`არტეფაქტები${artifacts.length > 0 ? ` (${artifacts.length})` : ''}`}
        icon="📎"
        expanded={artifactsExpanded}
        onToggle={() => setArtifactsExpanded(e => !e)}
      >
        {artifacts.length === 0 ? (
          <div style={{ fontSize: 11, color: 'var(--color-text-muted)', padding: '4px 0' }}>
            ჯერ არტეფაქტები არ არის
          </div>
        ) : (
          artifacts.map(artifact => {
            const meta = TYPE_META[artifact.type] ?? TYPE_META['flow']!
            return (
              <button
                key={artifact.id}
                onClick={() => onArtifactClick(artifact)}
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  gap: 8,
                  width: '100%',
                  padding: '6px 8px',
                  background: 'none',
                  border: '1px solid transparent',
                  borderRadius: 8,
                  cursor: 'pointer',
                  fontFamily: 'inherit',
                  textAlign: 'left',
                  transition: 'all 0.15s',
                  marginBottom: 2,
                }}
                onMouseEnter={e => {
                  e.currentTarget.style.background = 'var(--color-surface-dim)'
                  e.currentTarget.style.borderColor = 'var(--color-border)'
                }}
                onMouseLeave={e => {
                  e.currentTarget.style.background = 'none'
                  e.currentTarget.style.borderColor = 'transparent'
                }}
              >
                <span style={{ fontSize: 14, color: meta.color }}>{meta.icon}</span>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{
                    fontSize: 11.5,
                    fontWeight: 500,
                    color: 'var(--color-text)',
                    whiteSpace: 'nowrap',
                    overflow: 'hidden',
                    textOverflow: 'ellipsis',
                  }}>
                    {artifact.title}
                  </div>
                  {artifact.subtitle && (
                    <div style={{ fontSize: 9.5, color: 'var(--color-text-muted)', marginTop: 1 }}>
                      {artifact.subtitle}
                    </div>
                  )}
                </div>
                <span style={{ fontSize: 11, color: 'var(--color-text-muted)' }}>→</span>
              </button>
            )
          })
        )}
      </CollapsibleSection>

      {/* Context / Skills */}
      <CollapsibleSection
        title="კონტექსტი"
        icon="⚙"
        expanded={contextExpanded}
        onToggle={() => setContextExpanded(e => !e)}
      >
        {contextItems.length === 0 ? (
          <div style={{ fontSize: 11, color: 'var(--color-text-muted)', padding: '4px 0' }}>
            აქტიური skills არ არის
          </div>
        ) : (
          contextItems.map((item, i) => (
            <div
              key={i}
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: 6,
                padding: '3px 0',
                fontSize: 11,
              }}
            >
              <span
                style={{
                  fontSize: 9,
                  fontWeight: 700,
                  padding: '1px 4px',
                  borderRadius: 3,
                  background: item.tag === 'SKILL'
                    ? 'var(--color-primary-soft)'
                    : 'var(--color-accent-soft)',
                  color: item.tag === 'SKILL'
                    ? 'var(--color-primary)'
                    : 'var(--color-accent)',
                }}
              >
                {item.tag}
              </span>
              <span style={{ color: 'var(--color-text-sec)' }}>{item.label}</span>
              {item.detail && (
                <span style={{ color: 'var(--color-text-muted)', fontSize: 10 }}>{item.detail}</span>
              )}
            </div>
          ))
        )}
      </CollapsibleSection>
    </div>
  )
}
