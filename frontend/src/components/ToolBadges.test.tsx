import { render, screen, fireEvent } from '@testing-library/react'
import { describe, it, expect } from 'vitest'
import ToolBadges from './ToolBadges'

describe('ToolBadges', () => {
  it('renders nothing when no tools', () => {
    const { container } = render(<ToolBadges tools={[]} />)
    expect(container.firstChild).toBeNull()
  })

  it('shows collapsed summary for done tools', () => {
    render(
      <ToolBadges
        tools={[
          { tool: 'create_flow', status: 'done' },
          { tool: 'add_node', status: 'done' },
        ]}
      />,
    )
    expect(screen.getByText(/2 სამუშაო შესრულდა/)).toBeInTheDocument()
  })

  it('shows running tool name when in progress', () => {
    render(
      <ToolBadges
        tools={[
          { tool: 'create_flow', status: 'running' },
        ]}
      />,
    )
    expect(screen.getByText(/ფლოუს შექმნა\.\.\./)).toBeInTheDocument()
  })

  it('expands to show individual tools on click', () => {
    render(
      <ToolBadges
        tools={[
          { tool: 'create_flow', status: 'done' },
          { tool: 'add_node', status: 'done' },
        ]}
      />,
    )

    // Click to expand
    fireEvent.click(screen.getByText(/2 სამუშაო შესრულდა/))

    // Individual tools visible
    expect(screen.getByText(/ფლოუს შექმნა/)).toBeInTheDocument()
    expect(screen.getByText(/ნაბიჯის დამატება/)).toBeInTheDocument()
  })
})
