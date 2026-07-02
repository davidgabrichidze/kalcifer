import { describe, expect, it } from 'vitest'
import { type Node } from '@xyflow/react'
import { convertGraphToReactFlow, convertReactFlowToGraph } from './flowGraphUtils'
import { type FlowGraph } from '../../lib/api'

describe('node config round-trip', () => {
  const graph: FlowGraph = {
    nodes: [
      { id: 'e1', type: 'send_email', config: { subject: 'Hi', body: 'Welcome' } },
      { id: 'x1', type: 'exit', config: {} },
    ],
    edges: [{ source: 'e1', target: 'x1' }],
  }

  it('carries each node config onto its React Flow node data', () => {
    const { nodes } = convertGraphToReactFlow(graph)
    const email = nodes.find(n => n.id === 'e1')!
    expect((email.data as { config: Record<string, unknown> }).config).toEqual({
      subject: 'Hi',
      body: 'Welcome',
    })
  })

  it('persists an edited node config back into the graph', () => {
    const { nodes, edges } = convertGraphToReactFlow(graph)

    // Simulate the config panel editing the subject on the email node.
    const edited = nodes.map(n =>
      n.id === 'e1'
        ? { ...n, data: { ...n.data, config: { subject: 'Updated', body: 'Welcome' } } }
        : n,
    )

    const result = convertReactFlowToGraph(edited, edges, graph)
    const email = result.nodes.find(n => n.id === 'e1')!
    expect(email.config).toEqual({ subject: 'Updated', body: 'Welcome' })
  })

  it('falls back to the original graph config when a node carries none', () => {
    // A node that never entered the editor's data (no data.config).
    const rfNodes: Node[] = [
      { id: 'e1', type: 'flowNode', position: { x: 0, y: 0 }, data: { type: 'send_email', label: 'Email' } },
    ]
    const result = convertReactFlowToGraph(rfNodes, [], graph)
    expect(result.nodes[0]!.config).toEqual({ subject: 'Hi', body: 'Welcome' })
  })
})
