import { describe, expect, it } from 'vitest'
import { type Node } from '@xyflow/react'
import { convertGraphToReactFlow, convertReactFlowToGraph } from './flowGraphUtils'
import { type FlowGraph } from '../../lib/api'

describe('node groups persistence', () => {
  const groupedGraph: FlowGraph = {
    nodes: [
      { id: 'a', type: 'wait', config: { _editor: { group: { id: 'g1', label: 'Warmup' } } } },
      { id: 'b', type: 'send_email', config: { _editor: { group: { id: 'g1', label: 'Warmup' } } } },
      { id: 'c', type: 'exit', config: {} },
    ],
    edges: [
      { source: 'a', target: 'b' },
      { source: 'b', target: 'c' },
    ],
  }

  it('reconstructs a group container from member configs', () => {
    const { nodes } = convertGraphToReactFlow(groupedGraph)

    const group = nodes.find(n => n.type === 'groupNode')
    expect(group).toBeDefined()
    expect(group!.id).toBe('g1')
    expect((group!.data as { label: string }).label).toBe('Warmup')

    const memberA = nodes.find(n => n.id === 'a')!
    const memberB = nodes.find(n => n.id === 'b')!
    const outsider = nodes.find(n => n.id === 'c')!

    expect(memberA.parentId).toBe('g1')
    expect(memberB.parentId).toBe('g1')
    expect(outsider.parentId).toBeUndefined()

    // Parents must precede children in the node array
    expect(nodes.findIndex(n => n.id === 'g1')).toBeLessThan(nodes.findIndex(n => n.id === 'a'))
  })

  it('round-trips group membership back into configs', () => {
    const { nodes, edges } = convertGraphToReactFlow(groupedGraph)
    const graph = convertReactFlowToGraph(nodes, edges, groupedGraph)

    expect(graph.nodes.map(n => n.id).sort()).toEqual(['a', 'b', 'c'])

    const a = graph.nodes.find(n => n.id === 'a')!
    const c = graph.nodes.find(n => n.id === 'c')!
    expect((a.config._editor as { group: { id: string; label: string } }).group).toEqual({
      id: 'g1',
      label: 'Warmup',
    })
    expect(c.config._editor).toBeUndefined()
  })

  it('stamps membership when nodes are newly grouped in the canvas', () => {
    const rfNodes: Node[] = [
      {
        id: 'g2',
        type: 'groupNode',
        position: { x: 0, y: 0 },
        data: { label: 'Batch' },
      },
      {
        id: 'a',
        type: 'flowNode',
        position: { x: 40, y: 40 },
        parentId: 'g2',
        data: { type: 'wait', label: 'Wait' },
      },
      {
        id: 'b',
        type: 'flowNode',
        position: { x: 300, y: 40 },
        data: { type: 'exit', label: 'Exit' },
      },
    ]

    const graph = convertReactFlowToGraph(rfNodes, [], null)

    expect(graph.nodes).toHaveLength(2)

    const a = graph.nodes.find(n => n.id === 'a')!
    expect((a.config._editor as { group: { id: string } }).group.id).toBe('g2')
  })

  it('clears stale membership after ungrouping', () => {
    const original: FlowGraph = {
      nodes: [
        { id: 'a', type: 'wait', config: { _editor: { group: { id: 'g1', label: 'Old' } } } },
      ],
      edges: [],
    }

    const ungrouped: Node[] = [
      {
        id: 'a',
        type: 'flowNode',
        position: { x: 0, y: 0 },
        data: { type: 'wait', label: 'Wait' },
      },
    ]

    const graph = convertReactFlowToGraph(ungrouped, [], original)
    expect(graph.nodes[0]!.config._editor).toBeUndefined()
  })
})
