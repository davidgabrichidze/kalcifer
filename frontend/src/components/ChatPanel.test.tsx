import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import { describe, it, expect, vi, beforeEach } from 'vitest'
import ChatPanel from './ChatPanel'

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
    expect(screen.getByTitle('Send')).toBeInTheDocument()
  })

  it('send button is disabled when input is empty', () => {
    render(<ChatPanel {...defaultProps} />)
    const sendBtn = screen.getByTitle('Send')
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
})
