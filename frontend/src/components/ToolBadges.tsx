import { useState } from 'react'
import { type ToolActivity } from '../lib/chat'

// Human-readable names for tools
const TOOL_LABELS: Record<string, string> = {
  classify_session: 'სესიის კლასიფიკაცია',
  list_flows: 'ფლოუების ჩამონათვალი',
  get_flow: 'ფლოუს დეტალები',
  get_flow_graph: 'გრაფის წაკითხვა',
  create_flow: 'ფლოუს შექმნა',
  add_node: 'ნაბიჯის დამატება',
  modify_node: 'ნაბიჯის შეცვლა',
  remove_node: 'ნაბიჯის წაშლა',
  list_node_types: 'ნაბიჯების ტიპები',
  analyze_flow: 'ფლოუს ანალიზი',
  debug_instance: 'ინსტანსის დიაგნოსტიკა',
  remember: 'დამახსოვრება',
  recall: 'გახსენება',
}

export { TOOL_LABELS }

type ToolBadgeVariant = 'minimal' | 'compact' | 'default'

interface ToolBadgesProps {
  tools: ToolActivity[]
  variant?: ToolBadgeVariant
}

export default function ToolBadges({ tools, variant = 'minimal' }: ToolBadgesProps) {
  const [expanded, setExpanded] = useState(false)

  if (tools.length === 0) return null

  const doneCount = tools.filter(t => t.status === 'done').length
  const runCount = tools.length - doneCount

  // ── Variant B: minimal — clickable summary, expands to show details ──
  if (variant === 'minimal') {
    const summary = runCount > 0
      ? `${TOOL_LABELS[tools.find(t => t.status !== 'done')!.tool] ?? tools.find(t => t.status !== 'done')!.tool}...`
      : `${doneCount} სამუშაო შესრულდა`

    return (
      <div>
        <button
          onClick={() => setExpanded(e => !e)}
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: 6,
            padding: '3px 8px',
            fontSize: 11,
            color: 'var(--color-text-muted)',
            background: 'transparent',
            border: `1px solid ${expanded ? 'var(--color-border)' : 'transparent'}`,
            borderRadius: 6,
            cursor: 'pointer',
            fontFamily: 'inherit',
            transition: 'all 0.15s',
          }}
        >
          <span style={{
            width: 5,
            height: 5,
            borderRadius: '50%',
            background: runCount > 0 ? 'var(--color-warn)' : 'var(--color-success)',
            animation: runCount > 0 ? 'pulse 1.2s infinite' : 'none',
            flexShrink: 0,
          }} />
          <span>{summary}</span>
          <span style={{
            fontSize: 8,
            transform: expanded ? 'rotate(180deg)' : 'none',
            transition: 'transform 0.15s',
            marginLeft: 2,
          }}>
            ▼
          </span>
        </button>

        {expanded && (
          <div style={{
            display: 'flex',
            flexDirection: 'column',
            gap: 2,
            padding: '4px 8px 2px',
            animation: 'fadeUp 0.15s ease',
          }}>
            {tools.map((t, i) => {
              const isDone = t.status === 'done'
              return (
                <div
                  key={i}
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    gap: 6,
                    fontSize: 10.5,
                    color: 'var(--color-text-muted)',
                    padding: '1px 0',
                  }}
                >
                  <span style={{
                    width: 4,
                    height: 4,
                    borderRadius: '50%',
                    background: isDone ? 'var(--color-success)' : 'var(--color-warn)',
                    flexShrink: 0,
                    animation: !isDone ? 'pulse 1.2s infinite' : 'none',
                  }} />
                  <span style={{ color: isDone ? 'var(--color-text-muted)' : 'var(--color-text-sec)' }}>
                    {TOOL_LABELS[t.tool] ?? t.tool}
                  </span>
                  {isDone && <span style={{ fontSize: 9, opacity: 0.5 }}>✓</span>}
                </div>
              )
            })}
          </div>
        )}
      </div>
    )
  }

  // ── Variant C: compact — small square badges ──
  if (variant === 'compact') {
    return (
      <div style={{ display: 'flex', alignItems: 'center', gap: 4, padding: '2px 0' }}>
        {tools.map((t, i) => {
          const isDone = t.status === 'done'
          return (
            <span
              key={i}
              title={TOOL_LABELS[t.tool] ?? t.tool}
              style={{
                width: 18,
                height: 18,
                borderRadius: 4,
                fontSize: 8,
                display: 'inline-flex',
                alignItems: 'center',
                justifyContent: 'center',
                background: isDone ? 'var(--color-success-soft)' : 'var(--color-warn-soft)',
                color: isDone ? 'var(--color-success)' : 'var(--color-warn)',
                border: `1px solid ${isDone ? 'rgba(108,196,128,0.15)' : 'rgba(224,184,96,0.15)'}`,
              }}
            >
              {isDone ? '✓' : '•'}
            </span>
          )
        })}
        <span style={{ fontSize: 10, color: 'var(--color-text-muted)', marginLeft: 4 }}>
          {tools.length} tool{tools.length > 1 ? 's' : ''}
        </span>
      </div>
    )
  }

  // ── Variant A: default — inline info badges ──
  return (
    <div style={{ display: 'flex', flexWrap: 'wrap', gap: 4 }}>
      {tools.map((t, i) => (
        <span
          key={i}
          style={{
            display: 'inline-flex',
            alignItems: 'center',
            gap: 5,
            padding: '3px 10px',
            borderRadius: 8,
            background: 'var(--color-info-soft)',
            color: 'var(--color-info)',
            fontSize: 11,
            border: '1px solid rgba(112,168,224,0.15)',
          }}
        >
          <span style={{
            width: 5,
            height: 5,
            borderRadius: '50%',
            background: t.status === 'done' ? 'var(--color-success)' : 'var(--color-warn)',
            animation: t.status === 'running' ? 'pulse 1.2s infinite' : 'none',
          }} />
          {TOOL_LABELS[t.tool] ?? t.tool}
          {t.status === 'done' && <span style={{ opacity: 0.7 }}>✓</span>}
        </span>
      ))}
    </div>
  )
}
