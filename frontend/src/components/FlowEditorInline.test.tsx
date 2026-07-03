import { render, screen, waitFor, fireEvent } from '@testing-library/react'
import { describe, it, expect, vi, beforeEach } from 'vitest'
import FlowEditorInline from './FlowEditorInline'
import { fetchFlow, fetchFlowVersions } from '../lib/api'

// Mock the API module
vi.mock('../lib/api', () => ({
  fetchFlow: vi.fn(() =>
    Promise.resolve({
      id: 'flow-123',
      name: 'Test Flow',
      status: 'draft',
      description: 'A test flow',
    }),
  ),
  fetchFlowVersions: vi.fn(() =>
    Promise.resolve([
      {
        id: 'ver-1',
        version_number: 1,
        status: 'draft',
        graph: {
          nodes: [
            { id: 'entry_1', type: 'webhook_entry', position: { x: 0, y: 0 }, config: {} },
            { id: 'exit_1', type: 'exit', position: { x: 200, y: 0 }, config: {} },
          ],
          edges: [{ source: 'entry_1', target: 'exit_1' }],
        },
      },
    ]),
  ),
  simulateFlow: vi.fn(),
  updateFlowVersion: vi.fn(),
  preflightFlow: vi.fn(),
  parseNodeWarnings: vi.fn(() => new Map()),
}))

// Mock useFlowSocket
vi.mock('../lib/useFlowSocket', () => ({
  useFlowSocket: vi.fn(() => ({
    connected: false,
    activeInstances: new Map(),
    completedNodes: new Map(),
    activeNodes: new Map(),
    failedNodes: new Map(),
  })),
}))

// Mock FlowCanvas
vi.mock('./FlowCanvas', () => ({
  default: ({
    flowGraph,
    onGraphChange,
  }: {
    flowGraph: { nodes: unknown[] } | null
    onGraphChange?: (nodes: unknown[], edges: unknown[]) => void
  }) => (
    <div data-testid="flow-canvas">
      <button data-testid="simulate-local-edit" onClick={() => onGraphChange?.([{ id: 'n1' }], [])}>
        edit
      </button>
      {flowGraph ? `${flowGraph.nodes.length} nodes` : 'no graph'}
    </div>
  ),
}))

// Mock editor sub-components
vi.mock('../pages/editor/NodePalette', () => ({
  NodePalette: () => null,
}))
vi.mock('../pages/editor/NodeConfigPanel', () => ({
  NodeConfigPanel: () => null,
}))
vi.mock('../pages/editor/flowGraphUtils', () => ({
  convertReactFlowToGraph: vi.fn(),
}))

describe('FlowEditorInline', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('shows loading state initially', () => {
    render(<FlowEditorInline flowId="flow-123" />)
    expect(screen.getByText('იტვირთება...')).toBeInTheDocument()
  })

  it('renders flow name after loading', async () => {
    render(<FlowEditorInline flowId="flow-123" />)

    await waitFor(() => {
      expect(screen.getByText('Test Flow')).toBeInTheDocument()
    })
  })

  it('renders flow status badge', async () => {
    render(<FlowEditorInline flowId="flow-123" />)

    await waitFor(() => {
      expect(screen.getByText('Draft')).toBeInTheDocument()
    })
  })

  it('renders version number', async () => {
    render(<FlowEditorInline flowId="flow-123" />)

    await waitFor(() => {
      expect(screen.getByText('v1')).toBeInTheDocument()
    })
  })

  it('renders mode buttons (edit, simulate, live)', async () => {
    render(<FlowEditorInline flowId="flow-123" />)

    await waitFor(() => {
      // Mode buttons are in toolbar-center; status label also shows ✎, so use getAllByText
      const editBtns = screen.getAllByText('✎')
      expect(editBtns.length).toBeGreaterThanOrEqual(1)
      expect(screen.getByText('▶')).toBeInTheDocument()
      expect(screen.getByText('◉')).toBeInTheDocument()
    })
  })

  it('renders canvas with flow graph', async () => {
    render(<FlowEditorInline flowId="flow-123" />)

    await waitFor(() => {
      expect(screen.getByTestId('flow-canvas')).toHaveTextContent('2 nodes')
    })
  })

  it('shows error state on fetch failure', async () => {
    const { fetchFlow } = await import('../lib/api')
    vi.mocked(fetchFlow).mockRejectedValueOnce(new Error('Network error'))

    render(<FlowEditorInline flowId="bad-id" />)

    await waitFor(() => {
      expect(screen.getByText(/Network error/)).toBeInTheDocument()
    })
  })

  it('renders open full editor button when callback provided', async () => {
    const onOpen = vi.fn()
    render(<FlowEditorInline flowId="flow-123" onOpenFullEditor={onOpen} />)

    await waitFor(() => {
      expect(screen.getByTitle('სრულ ედიტორში გახსნა')).toBeInTheDocument()
    })
  })

  it('renders save button (disabled when no changes)', async () => {
    render(<FlowEditorInline flowId="flow-123" />)

    await waitFor(() => {
      const saveBtn = screen.getByTitle('შენახვა (Ctrl+S)')
      expect(saveBtn).toBeDisabled()
    })
  })
})

describe('FlowEditorInline — version selection and refresh', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('loads the latest draft version, not the oldest version', async () => {
    vi.mocked(fetchFlowVersions).mockResolvedValueOnce([
      {
        id: 'ver-1',
        version_number: 1,
        status: 'published',
        graph: { nodes: [{ id: 'a', type: 'exit', position: { x: 0, y: 0 }, config: {} }], edges: [] },
      },
      {
        id: 'ver-2',
        version_number: 2,
        status: 'draft',
        graph: {
          nodes: [
            { id: 'a', type: 'event_entry', position: { x: 0, y: 0 }, config: {} },
            { id: 'b', type: 'wait', position: { x: 100, y: 0 }, config: {} },
            { id: 'c', type: 'exit', position: { x: 200, y: 0 }, config: {} },
          ],
          edges: [],
        },
      },
    ] as never)

    render(<FlowEditorInline flowId="flow-123" />)

    await waitFor(() => {
      expect(screen.getByText('3 nodes')).toBeInTheDocument()
    })
  })

  it('re-fetches when refreshToken changes and there are no local edits', async () => {
    const { rerender } = render(<FlowEditorInline flowId="flow-123" refreshToken={0} />)

    await waitFor(() => {
      expect(vi.mocked(fetchFlow)).toHaveBeenCalledTimes(1)
    })

    rerender(<FlowEditorInline flowId="flow-123" refreshToken={1} />)

    await waitFor(() => {
      expect(vi.mocked(fetchFlow)).toHaveBeenCalledTimes(2)
    })
  })

  it('shows a stale banner instead of clobbering unsaved local edits', async () => {
    const { rerender } = render(<FlowEditorInline flowId="flow-123" refreshToken={0} />)

    await waitFor(() => {
      expect(screen.getByTestId('flow-canvas')).toBeInTheDocument()
    })

    fireEvent.click(screen.getByTestId('simulate-local-edit'))

    rerender(<FlowEditorInline flowId="flow-123" refreshToken={1} />)

    await waitFor(() => {
      expect(screen.getByText(/AI-მ განაახლა გრაფი/)).toBeInTheDocument()
    })
    expect(vi.mocked(fetchFlow)).toHaveBeenCalledTimes(1)

    fireEvent.click(screen.getByText('ჩატვირთე ხელახლა'))

    await waitFor(() => {
      expect(vi.mocked(fetchFlow)).toHaveBeenCalledTimes(2)
    })
  })
})
