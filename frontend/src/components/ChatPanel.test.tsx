import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import { describe, it, expect } from 'vitest'
import ChatPanel from './ChatPanel'

describe('ChatPanel', () => {
  it('renders welcome state with Kalcifer branding', () => {
    render(<ChatPanel />)
    expect(screen.getByText('Kalcifer')).toBeInTheDocument()
    expect(screen.getByText('სახლის გული ცოცხალია')).toBeInTheDocument()
  })

  it('renders input with Georgian placeholder', () => {
    render(<ChatPanel />)
    expect(screen.getByPlaceholderText('მიამბე რა გინდა გააკეთო...')).toBeInTheDocument()
  })

  it('renders send button', () => {
    render(<ChatPanel />)
    expect(screen.getByTitle('Send')).toBeInTheDocument()
  })

  it('send button is disabled when input is empty', () => {
    render(<ChatPanel />)
    const sendBtn = screen.getByTitle('Send')
    expect(sendBtn).toBeDisabled()
  })

  it('sends a message on Enter', async () => {
    render(<ChatPanel />)
    const textarea = screen.getByPlaceholderText('მიამბე რა გინდა გააკეთო...')

    fireEvent.change(textarea, { target: { value: 'გამარჯობა' } })
    fireEvent.keyDown(textarea, { key: 'Enter', shiftKey: false })

    // User message appears
    expect(screen.getByText('გამარჯობა')).toBeInTheDocument()
    // Input cleared
    expect(textarea).toHaveValue('')
    // Typing indicator appears
    expect(screen.getByTestId('typing-indicator')).toBeInTheDocument()
  })

  it('shows AI response after delay', async () => {
    render(<ChatPanel />)
    const textarea = screen.getByPlaceholderText('მიამბე რა გინდა გააკეთო...')

    fireEvent.change(textarea, { target: { value: 'test' } })
    fireEvent.keyDown(textarea, { key: 'Enter', shiftKey: false })

    await waitFor(() => {
      expect(screen.getByText(/ცოცხალი ვიქნები/)).toBeInTheDocument()
    }, { timeout: 2000 })
  })

  it('does not send on Shift+Enter', () => {
    render(<ChatPanel />)
    const textarea = screen.getByPlaceholderText('მიამბე რა გინდა გააკეთო...')

    fireEvent.change(textarea, { target: { value: 'test' } })
    fireEvent.keyDown(textarea, { key: 'Enter', shiftKey: true })

    // Message not sent — no user avatar
    expect(screen.queryByText('DG')).not.toBeInTheDocument()
  })
})
