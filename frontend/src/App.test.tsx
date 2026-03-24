import { render, screen, fireEvent } from '@testing-library/react'
import { describe, it, expect } from 'vitest'
import App from './App'

describe('App', () => {
  it('renders TopBar with brand', () => {
    render(<App />)
    const els = screen.getAllByText('Kalcifer')
    expect(els.length).toBeGreaterThanOrEqual(1)
  })

  it('shows Work page with chat input by default', () => {
    render(<App />)
    expect(screen.getByPlaceholderText(/მიამბე/)).toBeInTheDocument()
  })

  it('navigates to Browse page', () => {
    render(<App />)
    fireEvent.click(screen.getByText('Browse'))
    expect(screen.getAllByText(/Flows/).length).toBeGreaterThanOrEqual(1)
  })

  it('renders Engine Room link in TopBar', () => {
    render(<App />)
    expect(screen.getByText('Engine Room')).toBeInTheDocument()
  })

  it('navigates to Engine Room via TopBar', () => {
    render(<App />)
    fireEvent.click(screen.getByText('Engine Room'))
    // EnginePage should render with some identifying content
    expect(screen.getByText(/Engine Room/)).toBeInTheDocument()
  })
})
