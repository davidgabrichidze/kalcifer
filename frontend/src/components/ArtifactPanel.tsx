import './artifact-panel.css'

export interface Artifact {
  id: string
  type: 'flow' | 'analysis' | 'memory' | 'debug' | 'graph'
  title: string
  subtitle?: string
  resourceId?: string
  data?: Record<string, unknown>
  timestamp: number
}

const TYPE_META: Record<string, { icon: string; color: string; action: string }> = {
  flow: { icon: '⚡', color: 'var(--color-primary)', action: 'ედიტორში გახსნა' },
  analysis: { icon: '📊', color: 'var(--color-info)', action: 'ანალიზის ნახვა' },
  memory: { icon: '🧠', color: 'var(--color-accent)', action: 'გახსენება' },
  debug: { icon: '🔍', color: 'var(--color-warn)', action: 'დიაგნოსტიკა' },
  graph: { icon: '🔀', color: 'var(--color-success)', action: 'გრაფის ნახვა' },
}

interface ArtifactPanelProps {
  artifacts: Artifact[]
  onArtifactClick: (artifact: Artifact) => void
}

export default function ArtifactPanel({ artifacts, onArtifactClick }: ArtifactPanelProps) {
  if (artifacts.length === 0) return null

  return (
    <div className="artifact-panel">
      <div className="artifact-header">
        <span className="artifact-header-icon">📎</span>
        <span className="artifact-header-title">არტეფაქტები</span>
        <span className="artifact-header-count">{artifacts.length}</span>
      </div>

      <div className="artifact-list">
        {artifacts.map(artifact => {
          const meta = TYPE_META[artifact.type] ?? TYPE_META['flow']!
          return (
            <button
              key={artifact.id}
              className="artifact-item"
              onClick={() => onArtifactClick(artifact)}
              title={meta.action}
            >
              <span className="artifact-icon" style={{ color: meta.color }}>
                {meta.icon}
              </span>
              <div className="artifact-info">
                <div className="artifact-title">{artifact.title}</div>
                {artifact.subtitle && (
                  <div className="artifact-subtitle">{artifact.subtitle}</div>
                )}
              </div>
              <span className="artifact-action">→</span>
            </button>
          )
        })}
      </div>
    </div>
  )
}
