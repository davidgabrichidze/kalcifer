import { useCallback, useRef } from 'react'

interface DragHandleProps {
  onDrag: (clientX: number) => void
}

export default function DragHandle({ onDrag }: DragHandleProps) {
  const draggingRef = useRef(false)

  const handleMouseDown = useCallback(
    (e: React.MouseEvent) => {
      e.preventDefault()
      draggingRef.current = true
      document.body.style.cursor = 'col-resize'
      document.body.style.userSelect = 'none'

      const handleMouseMove = (ev: MouseEvent) => {
        if (draggingRef.current) {
          onDrag(ev.clientX)
        }
      }

      const handleMouseUp = () => {
        draggingRef.current = false
        document.body.style.cursor = ''
        document.body.style.userSelect = ''
        document.removeEventListener('mousemove', handleMouseMove)
        document.removeEventListener('mouseup', handleMouseUp)
      }

      document.addEventListener('mousemove', handleMouseMove)
      document.addEventListener('mouseup', handleMouseUp)
    },
    [onDrag],
  )

  return (
    <div
      className="drag-handle"
      onMouseDown={handleMouseDown}
      role="separator"
      aria-orientation="vertical"
    >
      <div className="drag-handle-line" />
    </div>
  )
}
