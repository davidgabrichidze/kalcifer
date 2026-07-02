import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { useState } from 'react'
import ChatPanel from './ChatPanel'
import { streamChat } from '../lib/api'

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
