import { render, screen, fireEvent } from '@testing-library/react'
import { describe, it, expect, vi } from 'vitest'
import ThemeSwitcher from './ThemeSwitcher'
import { THEMES } from '../lib/themes'

describe('ThemeSwitcher', () => {
  it('renders a button for each theme', () => {
    render(<ThemeSwitcher current="hearth-light" onChange={() => {}} />)
    const buttons = screen.getAllByRole('button')
    expect(buttons).toHaveLength(THEMES.length)
  })

  it('calls onChange with theme id on click', () => {
    const onChange = vi.fn()
    render(<ThemeSwitcher current="hearth-light" onChange={onChange} />)

    const buttons = screen.getAllByRole('button')
    fireEvent.click(buttons[3]!) // command-dark (4th button)
    expect(onChange).toHaveBeenCalledWith(THEMES[3]!.id)
  })

  it('shows title with palette name and mode', () => {
    render(<ThemeSwitcher current="grove-light" onChange={() => {}} />)
    expect(screen.getByTitle('Hearth light')).toBeInTheDocument()
    expect(screen.getByTitle('Command dark')).toBeInTheDocument()
    expect(screen.getByTitle('Grove light')).toBeInTheDocument()
    expect(screen.getByTitle('Calcifer dark')).toBeInTheDocument()
  })
})
