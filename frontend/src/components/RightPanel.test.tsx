import { render, screen, fireEvent } from '@testing-library/react'
import { describe, it, expect, vi } from 'vitest'
import RightPanel from './RightPanel'

// Mock heavy components
vi.mock('./FlowCanvas', () => ({
  default: () => <div data-testid="flow-canvas">FlowCanvas</div>,
}))

vi.mock('./FlowEditorInline', () => ({
  default: ({ flowId }: { flowId: string }) => (
    <div data-testid="flow-editor">FlowEditor: {flowId}</div>
  ),
}))

const sidebarProps = {
  progressSteps: [],
  artifacts: [],
  contextItems: [],
  onArtifactClick: vi.fn(),
  editorContent: null,
  onBack: vi.fn(),
  onClose: vi.fn(),
}

describe('RightPanel', () => {
  it('renders sidebar mode with artifacts section', () => {
    render(<RightPanel mode="sidebar" {...sidebarProps} />)
    expect(screen.getAllByText(/არტეფაქტები/).length).toBeGreaterThanOrEqual(1)
  })

  it('renders editor mode with back and close buttons', () => {
    render(
      <RightPanel
        mode="editor"
        {...sidebarProps}
        editorContent={{ type: 'flow-editor', flowId: 'test-123' }}
      />,
    )
    expect(screen.getByTitle('უკან')).toBeInTheDocument()
    expect(screen.getByTitle('დახურვა')).toBeInTheDocument()
    expect(screen.getByTestId('flow-editor')).toBeInTheDocument()
  })

  it('calls onBack when back button clicked', () => {
    const onBack = vi.fn()
    render(
      <RightPanel
        mode="editor"
        {...sidebarProps}
        onBack={onBack}
        editorContent={{ type: 'flow-editor', flowId: 'test-123' }}
      />,
    )

    fireEvent.click(screen.getByTitle('უკან'))
    expect(onBack).toHaveBeenCalledOnce()
  })

  it('calls onClose when close button clicked', () => {
    const onClose = vi.fn()
    render(
      <RightPanel
        mode="editor"
        {...sidebarProps}
        onClose={onClose}
        editorContent={{ type: 'flow-editor', flowId: 'test-123' }}
      />,
    )

    fireEvent.click(screen.getByTitle('დახურვა'))
    expect(onClose).toHaveBeenCalledOnce()
  })

  it('shows flow canvas in editor mode', () => {
    render(
      <RightPanel
        mode="editor"
        {...sidebarProps}
        editorContent={{
          type: 'flow-canvas',
          flowGraph: { nodes: [{ id: 'n1', type: 'trigger', config: {} }], edges: [] },
        }}
      />,
    )
    expect(screen.getByTestId('flow-canvas')).toBeInTheDocument()
    expect(screen.getByText('1 nodes')).toBeInTheDocument()
  })

  it('shows artifacts in sidebar mode', () => {
    render(
      <RightPanel
        mode="sidebar"
        {...sidebarProps}
        artifacts={[
          { id: 'f1', type: 'flow', title: 'Test Flow', timestamp: Date.now() },
        ]}
      />,
    )
    expect(screen.getByText('Test Flow')).toBeInTheDocument()
  })
})
