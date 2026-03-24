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

  it('renders Work, Browse, and Engine Room nav links', () => {
    renderTopBar()
    expect(screen.getByText('Work')).toBeInTheDocument()
    expect(screen.getByText('Browse')).toBeInTheDocument()
    expect(screen.getByText('Engine Room')).toBeInTheDocument()
  })

  it('renders ThemeSwitcher trigger', () => {
    renderTopBar()
    expect(screen.getByTitle('Theme')).toBeInTheDocument()
  })
})
