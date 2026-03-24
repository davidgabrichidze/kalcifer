import { useCallback, useRef } from 'react'
import { type Node, type Edge } from '@xyflow/react'

interface Snapshot {
  nodes: Node[]
  edges: Edge[]
}

interface UndoRedoState {
  past: Snapshot[]
  future: Snapshot[]
}

const MAX_HISTORY = 50

/**
 * Manages undo/redo history for the flow graph editor.
 *
 * Call `takeSnapshot` before each user-driven mutation (add/delete/move node, connect edge).
 * Call `undo` or `redo` to restore. Both return the snapshot to apply, or null if empty.
 */
export function useUndoRedo() {
  const stateRef = useRef<UndoRedoState>({ past: [], future: [] })

  const takeSnapshot = useCallback((nodes: Node[], edges: Edge[]) => {
    const snapshot: Snapshot = {
      nodes: nodes.map(n => ({ ...n })),
      edges: edges.map(e => ({ ...e })),
    }
    const past = [...stateRef.current.past, snapshot]
    if (past.length > MAX_HISTORY) past.shift()
    stateRef.current = { past, future: [] }
  }, [])

  const undo = useCallback(
    (currentNodes: Node[], currentEdges: Edge[]): Snapshot | null => {
      const { past, future } = stateRef.current
      if (past.length === 0) return null

      const previous = past[past.length - 1]!
      const currentSnapshot: Snapshot = {
        nodes: currentNodes.map(n => ({ ...n })),
        edges: currentEdges.map(e => ({ ...e })),
      }

      stateRef.current = {
        past: past.slice(0, -1),
        future: [currentSnapshot, ...future],
      }
      return previous
    },
    [],
  )

  const redo = useCallback(
    (currentNodes: Node[], currentEdges: Edge[]): Snapshot | null => {
      const { past, future } = stateRef.current
      if (future.length === 0) return null

      const next = future[0]!
      const currentSnapshot: Snapshot = {
        nodes: currentNodes.map(n => ({ ...n })),
        edges: currentEdges.map(e => ({ ...e })),
      }

      stateRef.current = {
        past: [...past, currentSnapshot],
        future: future.slice(1),
      }
      return next
    },
    [],
  )

  const canUndo = useCallback(() => stateRef.current.past.length > 0, [])
  const canRedo = useCallback(() => stateRef.current.future.length > 0, [])

  const clear = useCallback(() => {
    stateRef.current = { past: [], future: [] }
  }, [])

  return { takeSnapshot, undo, redo, canUndo, canRedo, clear }
}
