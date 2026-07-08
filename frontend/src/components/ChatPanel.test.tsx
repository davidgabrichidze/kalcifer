import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { useState } from 'react'
import ChatPanel from './ChatPanel'
import { streamChat, fetchConversation } from '../lib/api'

// Mock the API module
vi.mock('../lib/api', () => ({
  streamChat: vi.fn((_messages, callbacks) => {
    // Simulate streaming with a small delay
    setTimeout(() => {
      callbacks.onDelta('მალე ')
      callbacks.onDelta('ცოცხალი ვიქნები.')
      callbacks.onDone('მალე ცოცხალი ვიქნები.')
    }, 50)
    return { abort: vi.fn() }
  }),
  fetchConversation: vi.fn(() => Promise.resolve({ messages: [] })),
}))

const defaultProps = {
  conversationId: null,
  sessionKind: null,
}

describe('ChatPanel', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('renders input with Georgian placeholder', () => {
    render(<ChatPanel {...defaultProps} />)
    expect(screen.getByPlaceholderText('მიამბე რა გინდა გააკეთო...')).toBeInTheDocument()
  })

  it('renders send button', () => {
    render(<ChatPanel {...defaultProps} />)
    expect(screen.getByTitle('გაგზავნა')).toBeInTheDocument()
  })

  it('send button is disabled when input is empty', () => {
    render(<ChatPanel {...defaultProps} />)
    const sendBtn = screen.getByTitle('გაგზავნა')
    expect(sendBtn).toBeDisabled()
  })

  it('sends a message on Enter', async () => {
    render(<ChatPanel {...defaultProps} />)
    const textarea = screen.getByPlaceholderText('მიამბე რა გინდა გააკეთო...')

    fireEvent.change(textarea, { target: { value: 'გამარჯობა' } })
    fireEvent.keyDown(textarea, { key: 'Enter', shiftKey: false })

    // User message appears
    expect(screen.getByText('გამარჯობა')).toBeInTheDocument()
    // Input cleared
    expect(textarea).toHaveValue('')
  })

  it('shows streamed AI response', async () => {
    render(<ChatPanel {...defaultProps} />)
    const textarea = screen.getByPlaceholderText('მიამბე რა გინდა გააკეთო...')

    fireEvent.change(textarea, { target: { value: 'test' } })
    fireEvent.keyDown(textarea, { key: 'Enter', shiftKey: false })

    await waitFor(() => {
      expect(screen.getByText(/ცოცხალი ვიქნები/)).toBeInTheDocument()
    }, { timeout: 2000 })
  })

  it('does not send on Shift+Enter', () => {
    render(<ChatPanel {...defaultProps} />)
    const textarea = screen.getByPlaceholderText('მიამბე რა გინდა გააკეთო...')

    fireEvent.change(textarea, { target: { value: 'test' } })
    fireEvent.keyDown(textarea, { key: 'Enter', shiftKey: true })

    // Message not sent — no user avatar
    expect(screen.queryByText('DG')).not.toBeInTheDocument()
  })

  it('sends initial message from welcome screen', async () => {
    const onSent = vi.fn()
    render(
      <ChatPanel
        {...defaultProps}
        initialMessage="ტესტი"
        onInitialMessageSent={onSent}
      />,
    )

    // User message from initial message (effect runs async)
    await waitFor(() => {
      expect(screen.getByText('ტესტი')).toBeInTheDocument()
    })
    expect(onSent).toHaveBeenCalled()
  })

  it('aborts the in-flight stream on unmount', async () => {
    const controller = new AbortController()
    const abortSpy = vi.spyOn(controller, 'abort')
    vi.mocked(streamChat).mockReturnValueOnce(controller)

    const { unmount } = render(<ChatPanel {...defaultProps} initialMessage="ჰეი" />)
    await waitFor(() => expect(streamChat).toHaveBeenCalled())

    unmount()
    expect(abortSpy).toHaveBeenCalled()
  })

  it('keeps the first reply when the new conversation id arrives mid-stream', async () => {
    const controller = new AbortController()
    const abortSpy = vi.spyOn(controller, 'abort')
    // Real flow: backend assigns the conversation id first (onInit), then the
    // reply streams a little later. onInit flips the parent's conversationId
    // prop, which used to abort this very stream.
    vi.mocked(streamChat).mockImplementationOnce((_messages, callbacks) => {
      setTimeout(() => callbacks.onInit?.('conv-new'), 10)
      setTimeout(() => {
        callbacks.onDelta('პასუხი ')
        callbacks.onDelta('პირველი.')
        callbacks.onDone('პასუხი პირველი.')
      }, 40)
      return controller
    })

    // Harness mirrors WorkPage: onConversationId drives the conversationId prop.
    function Harness() {
      const [cid, setCid] = useState<string | null>(null)
      return (
        <ChatPanel
          conversationId={cid}
          sessionKind={null}
          initialMessage="გამარჯობა"
          onConversationId={setCid}
        />
      )
    }

    render(<Harness />)

    await waitFor(
      () => {
        expect(screen.getByText(/პირველი/)).toBeInTheDocument()
      },
      { timeout: 2000 },
    )

    // The stream that produced the reply must not have been aborted by the
    // conversationId change it triggered.
    expect(abortSpy).not.toHaveBeenCalled()
  })
})

describe('ChatPanel — flow mutation notifications', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  function streamWithToolDone(tool: string, result: unknown) {
    vi.mocked(streamChat).mockImplementation((_messages, callbacks) => {
      setTimeout(() => {
        callbacks.onToolDone?.(tool, JSON.stringify(result))
        callbacks.onDone?.('done')
      }, 10)
      return new AbortController()
    })
  }

  async function sendMessage() {
    const textarea = screen.getByPlaceholderText('მიამბე რა გინდა გააკეთო...')
    fireEvent.change(textarea, { target: { value: 'დაამატე ნაბიჯი' } })
    fireEvent.keyDown(textarea, { key: 'Enter', shiftKey: false })
  }

  it('fires onFlowMutated when add_node completes', async () => {
    const onFlowMutated = vi.fn()
    streamWithToolDone('add_node', { flow_id: 'flow-42', added_node: 'wait_1' })

    render(<ChatPanel {...defaultProps} onFlowMutated={onFlowMutated} />)
    await sendMessage()

    await waitFor(() => {
      expect(onFlowMutated).toHaveBeenCalledWith('flow-42')
    })
  })

  it('fires onFlowMutated with the new flow id when create_flow completes', async () => {
    const onFlowMutated = vi.fn()
    streamWithToolDone('create_flow', { id: 'flow-77', name: 'ახალი', graph: { nodes: [], edges: [] } })

    render(<ChatPanel {...defaultProps} onFlowMutated={onFlowMutated} />)
    await sendMessage()

    await waitFor(() => {
      expect(onFlowMutated).toHaveBeenCalledWith('flow-77')
    })
  })

  it('does not fire onFlowMutated for read-only tools', async () => {
    const onFlowMutated = vi.fn()
    streamWithToolDone('get_flow_graph', { flow_id: 'flow-42', nodes: [], edges: [] })

    render(<ChatPanel {...defaultProps} onFlowMutated={onFlowMutated} />)
    await sendMessage()

    // Wait for the stream to settle (tool badge summary confirms onToolDone fired)
    await waitFor(() => {
      expect(screen.getByText(/სამუშაო შესრულდა/)).toBeInTheDocument()
    })
    expect(onFlowMutated).not.toHaveBeenCalled()
  })

  it('never force-opens the editor on a tool call — only emits an artifact card', async () => {
    const onContextContent = vi.fn()
    const onArtifact = vi.fn()
    streamWithToolDone('create_flow', { id: 'flow-77', name: 'ახალი', graph: { nodes: [], edges: [] } })

    render(<ChatPanel {...defaultProps} onContextContent={onContextContent} onArtifact={onArtifact} />)
    await sendMessage()

    await waitFor(() => {
      expect(onArtifact).toHaveBeenCalledWith(
        expect.objectContaining({ type: 'flow', resourceId: 'flow-77' }),
      )
    })
    expect(onContextContent).not.toHaveBeenCalled()
  })

  it('emits a flow artifact when add_node completes, so the card stays fresh', async () => {
    const onArtifact = vi.fn()
    streamWithToolDone('add_node', {
      flow_id: 'flow-42',
      added_node: 'wait_1',
      total_nodes: 4,
      total_edges: 3,
      current_nodes: [],
    })

    render(<ChatPanel {...defaultProps} onArtifact={onArtifact} />)
    await sendMessage()

    await waitFor(() => {
      expect(onArtifact).toHaveBeenCalledWith(
        expect.objectContaining({ id: 'flow-flow-42', type: 'flow', resourceId: 'flow-42', subtitle: '4 ნაბიჯი' }),
      )
    })
  })
})

describe('ChatPanel — reopening a flow-linked conversation', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('shows the linked flow as an artifact card — does not force-open the editor', async () => {
    vi.mocked(fetchConversation).mockResolvedValueOnce({
      id: 'conv-1',
      title: 'A/B ტესტი',
      kind: 'campaign',
      status: 'active',
      entity_type: 'flow',
      entity_id: 'flow-55',
      inserted_at: '2026-07-08T13:12:12Z',
      updated_at: '2026-07-08T13:47:45Z',
      messages: [],
    })
    const onContextContent = vi.fn()
    const onArtifact = vi.fn()

    render(
      <ChatPanel
        {...defaultProps}
        conversationId="conv-1"
        onContextContent={onContextContent}
        onArtifact={onArtifact}
      />,
    )

    await waitFor(() => {
      expect(onArtifact).toHaveBeenCalledWith(
        expect.objectContaining({ type: 'flow', resourceId: 'flow-55' }),
      )
    })
    expect(onContextContent).not.toHaveBeenCalled()
  })

  it('does not emit an artifact for a conversation with no linked flow', async () => {
    vi.mocked(fetchConversation).mockResolvedValueOnce({
      id: 'conv-2',
      title: 'ჩვეულებრივი საუბარი',
      kind: 'analysis',
      status: 'active',
      entity_type: null,
      entity_id: null,
      inserted_at: '2026-07-08T13:12:12Z',
      updated_at: '2026-07-08T13:47:45Z',
      messages: [],
    })
    const onArtifact = vi.fn()

    render(
      <ChatPanel
        {...defaultProps}
        conversationId="conv-2"
        onArtifact={onArtifact}
      />,
    )

    await waitFor(() => {
      expect(fetchConversation).toHaveBeenCalledWith('conv-2')
    })
    expect(onArtifact).not.toHaveBeenCalled()
  })
})
