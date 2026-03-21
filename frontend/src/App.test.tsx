import { render, screen } from '@testing-library/react'
import { describe, it, expect } from 'vitest'
import App from './App'

describe('App', () => {
  it('renders Kalcifer heading', () => {
    render(<App />)
    expect(screen.getByText('Kalcifer')).toBeInTheDocument()
  })

  it('renders Georgian subtitle', () => {
    render(<App />)
    expect(screen.getByText('სახლის გული ცოცხალია')).toBeInTheDocument()
  })

  it('renders ThemeSwitcher', () => {
    render(<App />)
    const buttons = screen.getAllByRole('button')
    expect(buttons.length).toBeGreaterThanOrEqual(8)
  })
})
