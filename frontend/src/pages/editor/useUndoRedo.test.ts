import { describe, it, expect, beforeEach } from 'vitest'
import { renderHook, act } from '@testing-library/react'
import { useUndoRedo } from './useUndoRedo'
import { type Node, type Edge } from '@xyflow/react'

function makeNodes(ids: string[]): Node[] {
  return ids.map(id => ({
    id,
    type: 'flowNode',
    position: { x: 0, y: 0 },
    data: { label: id },
  }))
}

function makeEdges(pairs: [string, string][]): Edge[] {
  return pairs.map(([source, target]) => ({
    id: `${source}-${target}`,
    source,
    target,
  }))
}

describe('useUndoRedo', () => {
  let hook: { result: { current: ReturnType<typeof useUndoRedo> } }

  beforeEach(() => {
    hook = renderHook(() => useUndoRedo())
  })

  it('starts with no undo/redo available', () => {
    expect(hook.result.current.canUndo()).toBe(false)
    expect(hook.result.current.canRedo()).toBe(false)
  })

  it('can undo after taking a snapshot', () => {
    const nodesV1 = makeNodes(['a', 'b'])
    const edgesV1 = makeEdges([['a', 'b']])
    const nodesV2 = makeNodes(['a', 'b', 'c'])
    const edgesV2 = makeEdges([['a', 'b'], ['b', 'c']])

    act(() => hook.result.current.takeSnapshot(nodesV1, edgesV1))

    expect(hook.result.current.canUndo()).toBe(true)
    expect(hook.result.current.canRedo()).toBe(false)

    let result: ReturnType<typeof hook.result.current.undo>
    act(() => {
      result = hook.result.current.undo(nodesV2, edgesV2)
    })

    expect(result!).not.toBeNull()
    expect(result!.nodes.map((n: Node) => n.id)).toEqual(['a', 'b'])
    expect(result!.edges.map((e: Edge) => e.id)).toEqual(['a-b'])
  })

  it('can redo after undo', () => {
    const nodesV1 = makeNodes(['a'])
    const edgesV1: Edge[] = []
    const nodesV2 = makeNodes(['a', 'b'])
    const edgesV2 = makeEdges([['a', 'b']])

    act(() => hook.result.current.takeSnapshot(nodesV1, edgesV1))

    // Undo: restore V1
    act(() => { hook.result.current.undo(nodesV2, edgesV2) })

    expect(hook.result.current.canRedo()).toBe(true)

    // Redo: should return V2
    let result: ReturnType<typeof hook.result.current.redo>
    act(() => {
      result = hook.result.current.redo(nodesV1, edgesV1)
    })

    expect(result!).not.toBeNull()
    expect(result!.nodes.map((n: Node) => n.id)).toEqual(['a', 'b'])
  })

  it('clears redo stack when new snapshot is taken', () => {
    const n1 = makeNodes(['a'])
    const n2 = makeNodes(['a', 'b'])
    const n3 = makeNodes(['a', 'c'])

    act(() => hook.result.current.takeSnapshot(n1, []))
    act(() => { hook.result.current.undo(n2, []) })
    expect(hook.result.current.canRedo()).toBe(true)

    // Take new snapshot — clears redo
    act(() => hook.result.current.takeSnapshot(n3, []))
    expect(hook.result.current.canRedo()).toBe(false)
    expect(hook.result.current.canUndo()).toBe(true)
  })

  it('returns null when undoing with empty history', () => {
    let result: ReturnType<typeof hook.result.current.undo>
    act(() => {
      result = hook.result.current.undo(makeNodes(['a']), [])
    })
    expect(result!).toBeNull()
  })

  it('returns null when redoing with empty future', () => {
    let result: ReturnType<typeof hook.result.current.redo>
    act(() => {
      result = hook.result.current.redo(makeNodes(['a']), [])
    })
    expect(result!).toBeNull()
  })

  it('supports multiple undo steps', () => {
    const n1 = makeNodes(['a'])
    const n2 = makeNodes(['a', 'b'])
    const n3 = makeNodes(['a', 'b', 'c'])

    act(() => hook.result.current.takeSnapshot(n1, []))
    act(() => hook.result.current.takeSnapshot(n2, []))

    // First undo → V2
    let r1: ReturnType<typeof hook.result.current.undo>
    act(() => { r1 = hook.result.current.undo(n3, []) })
    expect(r1!.nodes.map(n => n.id)).toEqual(['a', 'b'])

    // Second undo → V1
    let r2: ReturnType<typeof hook.result.current.undo>
    act(() => { r2 = hook.result.current.undo(n2, []) })
    expect(r2!.nodes.map(n => n.id)).toEqual(['a'])

    // No more undo
    expect(hook.result.current.canUndo()).toBe(false)
  })

  it('clear resets all history', () => {
    act(() => hook.result.current.takeSnapshot(makeNodes(['a']), []))
    expect(hook.result.current.canUndo()).toBe(true)

    act(() => hook.result.current.clear())
    expect(hook.result.current.canUndo()).toBe(false)
    expect(hook.result.current.canRedo()).toBe(false)
  })
})
