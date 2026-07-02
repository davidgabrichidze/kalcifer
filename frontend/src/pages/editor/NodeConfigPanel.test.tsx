import { render, screen, fireEvent } from '@testing-library/react'
import { describe, it, expect, vi } from 'vitest'
import { NodeConfigPanel } from './NodeConfigPanel'

// The panel only calls the API for sub_flow nodes; keep it inert here.
vi.mock('../../lib/api', () => ({
  fetchFlows: vi.fn(() => Promise.resolve([])),
}))

function renderPanel(overrides = {}) {
  const props = {
    isOpen: true,
    nodeId: 'n1',
    nodeType: 'send_email',
    nodeLabel: 'Welcome email',
    nodeDescription: 'greets the user',
    nodeConfig: { subject: 'Hi' },
    onClose: vi.fn(),
    onSave: vi.fn(),
    onDelete: vi.fn(),
    ...overrides,
  }
  render(<NodeConfigPanel {...props} />)
  return props
}

describe('NodeConfigPanel', () => {
  it('emits a label patch when the title is edited', () => {
    const props = renderPanel()
    fireEvent.change(screen.getByPlaceholderText('Node title'), {
      target: { value: 'Renamed' },
    })
    expect(props.onSave).toHaveBeenCalledWith({ label: 'Renamed' })
  })

  it('emits a description patch when the description is edited', () => {
    const props = renderPanel()
    fireEvent.change(screen.getByPlaceholderText('Node description'), {
      target: { value: 'new desc' },
    })
    expect(props.onSave).toHaveBeenCalledWith({ description: 'new desc' })
  })

  it('merges type-specific field edits into the existing config', () => {
    const props = renderPanel()
    fireEvent.change(screen.getByPlaceholderText('მაგ: გამარჯობა {{name}}!'), {
      target: { value: 'Hello there' },
    })
    expect(props.onSave).toHaveBeenCalledWith({ config: { subject: 'Hello there' } })
  })

  it('Save emits the full patch and closes', () => {
    const props = renderPanel()
    fireEvent.click(screen.getByText('Save'))
    expect(props.onSave).toHaveBeenCalledWith({
      label: 'Welcome email',
      description: 'greets the user',
      config: { subject: 'Hi' },
    })
    expect(props.onClose).toHaveBeenCalled()
  })

  it('Delete calls onDelete', () => {
    const props = renderPanel()
    fireEvent.click(screen.getByText('Delete'))
    expect(props.onDelete).toHaveBeenCalled()
  })
})
