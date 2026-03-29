import { render, screen, fireEvent } from '@testing-library/react'
import { describe, it, expect, vi } from 'vitest'
import CollapsibleSection from './CollapsibleSection'

describe('CollapsibleSection', () => {
  it('renders title', () => {
    render(
      <CollapsibleSection title="Test Section" expanded={false} onToggle={() => {}}>
        <p>Content</p>
      </CollapsibleSection>,
    )
    expect(screen.getByText('Test Section')).toBeInTheDocument()
  })

  it('shows children when expanded', () => {
    render(
      <CollapsibleSection title="Test" expanded={true} onToggle={() => {}}>
        <p>Visible content</p>
      </CollapsibleSection>,
    )
    expect(screen.getByText('Visible content')).toBeInTheDocument()
  })

  it('hides children when collapsed', () => {
    render(
      <CollapsibleSection title="Test" expanded={false} onToggle={() => {}}>
        <p>Hidden content</p>
      </CollapsibleSection>,
    )
    expect(screen.queryByText('Hidden content')).not.toBeInTheDocument()
  })

  it('calls onToggle when header clicked', () => {
    const onToggle = vi.fn()
    render(
      <CollapsibleSection title="Click me" expanded={false} onToggle={onToggle}>
        <p>Content</p>
      </CollapsibleSection>,
    )
    fireEvent.click(screen.getByText('Click me'))
    expect(onToggle).toHaveBeenCalledOnce()
  })

  it('renders icon when provided', () => {
    render(
      <CollapsibleSection title="Test" icon="🔥" expanded={false} onToggle={() => {}}>
        <p>Content</p>
      </CollapsibleSection>,
    )
    expect(screen.getByText('🔥')).toBeInTheDocument()
  })

  it('sets aria-expanded correctly', () => {
    const { rerender } = render(
      <CollapsibleSection title="Test" expanded={false} onToggle={() => {}}>
        <p>Content</p>
      </CollapsibleSection>,
    )
    expect(screen.getByRole('button')).toHaveAttribute('aria-expanded', 'false')

    rerender(
      <CollapsibleSection title="Test" expanded={true} onToggle={() => {}}>
        <p>Content</p>
      </CollapsibleSection>,
    )
    expect(screen.getByRole('button')).toHaveAttribute('aria-expanded', 'true')
  })
})
