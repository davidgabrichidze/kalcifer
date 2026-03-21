import { render, screen, fireEvent } from '@testing-library/react'
import { describe, it, expect, vi } from 'vitest'
import ThemeSwitcher from './ThemeSwitcher'
import { THEMES } from '../lib/themes'

describe('ThemeSwitcher', () => {
  it('renders a trigger button', () => {
    render(<ThemeSwitcher current="hearth-light" onChange={() => {}} />)
    expect(screen.getByTitle('Theme')).toBeInTheDocument()
  })

  it('opens dropdown on click', () => {
    render(<ThemeSwitcher current="hearth-light" onChange={() => {}} />)
    fireEvent.click(screen.getByTitle('Theme'))
    // All 8 theme options visible
    expect(screen.getAllByRole('button')).toHaveLength(1 + THEMES.length)
  })

  it('calls onChange and closes on theme select', () => {
    const onChange = vi.fn()
    render(<ThemeSwitcher current="hearth-light" onChange={onChange} />)
    fireEvent.click(screen.getByTitle('Theme'))
    fireEvent.click(screen.getByTitle('Command dark'))
    expect(onChange).toHaveBeenCalledWith('command-dark')
    // Dropdown closed — only trigger button remains
    expect(screen.getAllByRole('button')).toHaveLength(1)
  })
})
