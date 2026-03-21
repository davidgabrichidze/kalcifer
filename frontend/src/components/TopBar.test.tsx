import { render, screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { describe, it, expect, vi } from 'vitest'
import TopBar from './TopBar'

function renderTopBar(theme = 'hearth-light' as const) {
  return render(
    <MemoryRouter>
      <TopBar theme={theme} onThemeChange={vi.fn()} />
    </MemoryRouter>
  )
}

describe('TopBar', () => {
  it('renders Kalcifer brand', () => {
    renderTopBar()
    expect(screen.getByText(/Kalcifer/)).toBeInTheDocument()
  })

  it('renders all 3 nav links', () => {
    renderTopBar()
    expect(screen.getByText('Work')).toBeInTheDocument()
    expect(screen.getByText('Engine Room')).toBeInTheDocument()
    expect(screen.getByText('Browse')).toBeInTheDocument()
  })

  it('does not render Editor nav link', () => {
    renderTopBar()
    expect(screen.queryByText('Editor')).not.toBeInTheDocument()
  })

  it('renders ThemeSwitcher buttons', () => {
    renderTopBar()
    const buttons = screen.getAllByRole('button')
    expect(buttons.length).toBeGreaterThanOrEqual(8)
  })
})
