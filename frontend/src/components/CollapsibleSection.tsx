import { type ReactNode } from 'react'

interface CollapsibleSectionProps {
  title: string
  icon?: ReactNode
  expanded: boolean
  onToggle: () => void
  children: ReactNode
}

export default function CollapsibleSection({
  title,
  icon,
  expanded,
  onToggle,
  children,
}: CollapsibleSectionProps) {
  return (
    <div className="collapsible-section">
      <button
        className="collapsible-header"
        onClick={onToggle}
        aria-expanded={expanded}
      >
        {icon && <span className="collapsible-icon">{icon}</span>}
        <span className="collapsible-title">{title}</span>
        <span
          className="collapsible-chevron"
          style={{ transform: expanded ? 'rotate(90deg)' : 'rotate(0deg)' }}
        >
          ›
        </span>
      </button>
      {expanded && (
        <div className="collapsible-body">
          {children}
        </div>
      )}
    </div>
  )
}
