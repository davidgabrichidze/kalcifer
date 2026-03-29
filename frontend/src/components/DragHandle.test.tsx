import { render, screen, fireEvent } from '@testing-library/react'
import { describe, it, expect, vi } from 'vitest'
import DragHandle from './DragHandle'

describe('DragHandle', () => {
  it('renders with separator role', () => {
    render(<DragHandle onDrag={() => {}} />)
    expect(screen.getByRole('separator')).toBeInTheDocument()
  })

  it('calls onDrag during mouse drag', () => {
    const onDrag = vi.fn()
    render(<DragHandle onDrag={onDrag} />)

    const handle = screen.getByRole('separator')

    fireEvent.mouseDown(handle)
    fireEvent.mouseMove(document, { clientX: 400 })
    fireEvent.mouseUp(document)

    expect(onDrag).toHaveBeenCalledWith(400)
  })

  it('does not call onDrag after mouseup', () => {
    const onDrag = vi.fn()
    render(<DragHandle onDrag={onDrag} />)

    const handle = screen.getByRole('separator')

    fireEvent.mouseDown(handle)
    fireEvent.mouseMove(document, { clientX: 400 })
    fireEvent.mouseUp(document)

    onDrag.mockClear()
    fireEvent.mouseMove(document, { clientX: 500 })

    expect(onDrag).not.toHaveBeenCalled()
  })
})
