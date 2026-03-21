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
    expect(screen.getByText('Kalcifer')).toBeInTheDocument()
  })

  it('renders Work and Browse nav links', () => {
    renderTopBar()
    expect(screen.getByText('Work')).toBeInTheDocument()
    expect(screen.getByText('Browse')).toBeInTheDocument()
  })

  it('does not render Engine Room in TopBar', () => {
    renderTopBar()
    expect(screen.queryByText('Engine Room')).not.toBeInTheDocument()
  })

  it('renders ThemeSwitcher buttons', () => {
    renderTopBar()
    const buttons = screen.getAllByRole('button')
    expect(buttons.length).toBeGreaterThanOrEqual(8)
  })
})
