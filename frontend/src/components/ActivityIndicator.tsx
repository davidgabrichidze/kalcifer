import { AgentActivity, AgentActivityStep } from '../lib/chat'
import './activity-indicator.css'

const NODE_LABELS: Record<string, string> = {
  agent: 'ასისტენტი',
  ai_think: 'აზროვნება',
  ai_decide: 'გადაწყვეტილება',
  ai_notify: 'შეტყობინება',
  webhook_entry: 'შესვლა',
  exit: 'დასრულება',
}

function stepLabel(step: AgentActivityStep): string {
  return step.label || NODE_LABELS[step.nodeType] || step.nodeType
}

function formatDuration(ms: number): string {
  if (ms < 1000) return `${ms}ms`
  return `${(ms / 1000).toFixed(1)}s`
}

interface Props {
  activity: AgentActivity
  expanded: boolean
  onToggle: () => void
}

export default function ActivityIndicator({ activity, expanded, onToggle }: Props) {
  const isDone = activity.status === 'done'
  const isFailed = activity.status === 'failed'
  const visibleSteps = activity.steps.filter(s => s.nodeType !== 'webhook_entry' && s.nodeType !== 'exit')

  if (isDone && visibleSteps.length === 0) return null

  return (
    <div className={`activity-indicator ${isDone ? 'done' : ''} ${isFailed ? 'failed' : ''}`}>
      <button className="activity-header" onClick={onToggle}>
        <span className="activity-summary">
          {isDone ? (
            <>
              <span className="activity-icon done">✓</span>
              <span>კალციფერი დაასრულა</span>
              {activity.durationMs != null && (
                <span className="activity-duration">({formatDuration(activity.durationMs)})</span>
              )}
            </>
          ) : isFailed ? (
            <>
              <span className="activity-icon failed">✗</span>
              <span>შეცდომა</span>
            </>
          ) : (
            <>
              <span className="activity-icon working">🔥</span>
              <span>კალციფერი მუშაობს...</span>
              <StepsSummary steps={visibleSteps} />
            </>
          )}
        </span>
        <span className="activity-toggle">{expanded ? '▴' : '▾'}</span>
      </button>

      {expanded && visibleSteps.length > 0 && (
        <div className="activity-steps">
          {visibleSteps.map(step => (
            <StepRow key={step.nodeId} step={step} />
          ))}
        </div>
      )}
    </div>
  )
}

function StepsSummary({ steps }: { steps: AgentActivityStep[] }) {
  const completed = steps.filter(s => s.status === 'completed')
  const running = steps.find(s => s.status === 'running')

  return (
    <span className="steps-summary">
      {completed.length > 0 && (
        <span className="steps-completed">
          {completed.map(s => stepLabel(s)).join(', ')} ✓
        </span>
      )}
      {running && (
        <span className="steps-running">
          ▸ {stepLabel(running)}
        </span>
      )}
    </span>
  )
}

function StepRow({ step }: { step: AgentActivityStep }) {
  const duration =
    step.completedAt && step.startedAt
      ? formatDuration(step.completedAt - step.startedAt)
      : null

  return (
    <div className={`activity-step ${step.status}`}>
      <span className="step-dot" />
      <span className="step-label">{stepLabel(step)}</span>
      {duration && <span className="step-duration">{duration}</span>}
    </div>
  )
}
