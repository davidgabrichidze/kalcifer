import { render, screen, fireEvent } from '@testing-library/react'
import { describe, it, expect } from 'vitest'
import App from './App'

describe('App', () => {
  it('renders TopBar with brand', () => {
    render(<App />)
    expect(screen.getByText(/Kalcifer/)).toBeInTheDocument()
  })

  it('shows Work page by default', () => {
    render(<App />)
    expect(screen.getByText(/AI chat/)).toBeInTheDocument()
  })

  it('navigates to Engine Room page', () => {
    render(<App />)
    fireEvent.click(screen.getByText('Engine Room'))
    expect(screen.getByText(/Live monitoring/)).toBeInTheDocument()
  })

  it('navigates to Browse page', () => {
    render(<App />)
    fireEvent.click(screen.getByText('Browse'))
    expect(screen.getByText(/Flow library/)).toBeInTheDocument()
  })
})
