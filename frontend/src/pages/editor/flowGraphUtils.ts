import { type Node, type Edge } from '@xyflow/react'
import { type FlowGraph, type FlowGraphNode } from '../../lib/api'
import { getNodeType } from './nodeTypes'

/**
 * Auto-layout algorithm: BFS from root nodes, assign positions in layers
 */
export function autoLayoutNodes(
  graphNodes: Array<{ id: string; type: string }>,
  graphEdges: Array<{ source: string; target: string }>,
): Record<string, { x: number; y: number }> {
  const positions: Record<string, { x: number; y: number }> = {}

  if (graphNodes.length === 0) return positions

  // Find root nodes (no incoming edges)
  const hasIncoming = new Set(graphEdges.map(e => e.target))
  const roots = graphNodes.filter(n => !hasIncoming.has(n.id))

  if (roots.length === 0 && graphNodes.length > 0) {
    // If no roots, start from first node
    roots.push(graphNodes[0]!)
  }

  // BFS to assign layers
  const layers: Map<string, number> = new Map()
  const visited = new Set<string>()
  const queue: Array<[string, number]> = roots.map(r => [r.id, 0])

  while (queue.length > 0) {
    const [nodeId, layer] = queue.shift()!
    if (visited.has(nodeId)) continue

    visited.add(nodeId)
    layers.set(nodeId, layer)

    // Find children
    graphEdges.forEach(edge => {
      if (edge.source === nodeId && !visited.has(edge.target)) {
        queue.push([edge.target, layer + 1])
      }
    })
  }

  // Assign positions
  const nodesByLayer = new Map<number, string[]>()
  layers.forEach((layer, nodeId) => {
    if (!nodesByLayer.has(layer)) nodesByLayer.set(layer, [])
    nodesByLayer.get(layer)!.push(nodeId)
  })

  const LAYER_HEIGHT = 160
  const H_SPACING = 240

  nodesByLayer.forEach((nodeIds, layer) => {
    const totalWidth = nodeIds.length * H_SPACING
    const startX = -totalWidth / 2

    nodeIds.forEach((nodeId, index) => {
      positions[nodeId] = {
        x: startX + index * H_SPACING,
        y: layer * LAYER_HEIGHT,
      }
    })
  })

  return positions
}

/**
 * Extract a human-readable summary from a node's config.
 * Different node types store their key info in different config fields.
 */
export function summarizeNodeConfig(gn: FlowGraphNode): string {
  const c = gn.config || {}
  switch (gn.type) {
    case 'send_email':
      return (c.subject as string) || (c.template_id as string) || ''
    case 'send_sms':
    case 'send_whatsapp':
      return (c.template_id as string) || (c.body as string) || ''
    case 'send_push':
      return (c.title as string) || ''
    case 'condition':
    case 'check_segment':
      return (c.expression as string) || (c.field as string) || (c.segment_field as string) || ''
    case 'wait':
      return (c.duration as string) || ''
    case 'wait_until':
      return (c.datetime as string) || (c.time as string) || ''
    case 'wait_for_event':
      return (c.event_name as string) || ''
    case 'ab_split':
      return Array.isArray(c.variants)
        ? (c.variants as Array<{ key?: string }>).map(v => v.key).filter(Boolean).join(' / ')
        : ''
    case 'call_webhook':
      return (c.url as string) || ''
    case 'add_tag':
      return (c.tag as string) || ''
    case 'segment_entry':
    case 'event_entry':
      return (c.event_name as string) || (c.segment as string) || ''
    default:
      return ''
  }
}

/**
 * Convert backend FlowGraph to React Flow nodes/edges with auto-layout
 */
interface EditorGroupMeta {
  id: string
  label?: string
}

/** Reads editor-only group metadata persisted in a node's config. */
export function nodeGroupMeta(config: Record<string, unknown> | undefined): EditorGroupMeta | null {
  const editor = config?._editor as { group?: EditorGroupMeta } | undefined
  const group = editor?.group
  return group?.id ? group : null
}

const GROUP_PADDING = 40
const NODE_EST_WIDTH = 220
const NODE_EST_HEIGHT = 90

export function convertGraphToReactFlow(
  flowGraph: FlowGraph,
): { nodes: Node[]; edges: Edge[] } {
  const positions = autoLayoutNodes(flowGraph.nodes, flowGraph.edges)

  let nodes = flowGraph.nodes.map(gn => {
    const pos = positions[gn.id] || { x: 0, y: 0 }
    const nodeTypeMeta = getNodeType(gn.type)
    return {
      id: gn.id,
      type: 'flowNode',
      position: pos,
      data: {
        label: nodeTypeMeta?.label || gn.type,
        type: gn.type,
        description: summarizeNodeConfig(gn),
        configDetail: '',
        // Carry the node's config so the config panel can read/edit it and
        // the reverse conversion can persist edits (see convertReactFlowToGraph).
        config: gn.config || {},
      },
    } as Node
  })

  // Reconstruct visual group containers from members' _editor.group config
  const groups = new Map<string, { label: string; members: string[] }>()
  flowGraph.nodes.forEach(gn => {
    const meta = nodeGroupMeta(gn.config)
    if (!meta) return
    const entry = groups.get(meta.id) || { label: meta.label || 'Group', members: [] }
    if (meta.label) entry.label = meta.label
    entry.members.push(gn.id)
    groups.set(meta.id, entry)
  })

  if (groups.size > 0) {
    const groupNodes: Node[] = []
    const memberToGroup = new Map<string, { groupId: string; origin: { x: number; y: number } }>()

    groups.forEach(({ label, members }, groupId) => {
      const memberNodes = nodes.filter(n => members.includes(n.id))
      if (memberNodes.length === 0) return

      const minX = Math.min(...memberNodes.map(n => n.position.x)) - GROUP_PADDING
      const minY = Math.min(...memberNodes.map(n => n.position.y)) - GROUP_PADDING
      const maxX = Math.max(...memberNodes.map(n => n.position.x + NODE_EST_WIDTH)) + GROUP_PADDING
      const maxY = Math.max(...memberNodes.map(n => n.position.y + NODE_EST_HEIGHT)) + GROUP_PADDING

      groupNodes.push({
        id: groupId,
        type: 'groupNode',
        position: { x: minX, y: minY },
        style: { width: maxX - minX, height: maxY - minY },
        data: { label },
      } as Node)

      members.forEach(id => memberToGroup.set(id, { groupId, origin: { x: minX, y: minY } }))
    })

    nodes = nodes.map(n => {
      const membership = memberToGroup.get(n.id)
      if (!membership) return n
      return {
        ...n,
        parentId: membership.groupId,
        extent: 'parent' as const,
        position: {
          x: n.position.x - membership.origin.x,
          y: n.position.y - membership.origin.y,
        },
      }
    })

    // React Flow requires parent nodes to appear before their children
    nodes = [...groupNodes, ...nodes]
  }

  const edges = flowGraph.edges.map(ge => ({
    id: `${ge.source}-${ge.target}${ge.branch ? `-${ge.branch}` : ''}`,
    source: ge.source,
    target: ge.target,
    // Connect to the correct handle on branching nodes
    ...(ge.branch ? { sourceHandle: ge.branch } : {}),
    label: ge.branch === 'true' ? '✓ yes'
      : ge.branch === 'false' ? '✗ no'
        : '',
    labelStyle: ge.branch
      ? {
          fontSize: 10,
          fontWeight: 600,
          fill: ge.branch === 'true' ? 'var(--color-success)' : 'var(--color-danger)',
        }
      : {},
    labelBgStyle: ge.branch
      ? { fill: 'var(--color-surface)', fillOpacity: 0.9 }
      : {},
    labelBgPadding: ge.branch ? [4, 2] as [number, number] : undefined,
    labelBgBorderRadius: 4,
    style: ge.branch === 'true'
      ? { stroke: 'var(--color-success)', strokeWidth: 2 }
      : ge.branch === 'false'
        ? { stroke: 'var(--color-danger)', strokeWidth: 2 }
        : {},
    animated: ge.branch === 'true',
  }))

  return { nodes, edges }
}

/**
 * Convert React Flow nodes/edges back to backend FlowGraph format.
 * Preserves node configs from the original graph.
 */
export function convertReactFlowToGraph(
  rfNodes: Node[],
  rfEdges: Edge[],
  originalGraph?: FlowGraph | null,
): FlowGraph {
  // Build config lookup from original graph
  const configMap = new Map<string, Record<string, unknown>>()
  if (originalGraph) {
    for (const n of originalGraph.nodes) {
      configMap.set(n.id, n.config)
    }
  }

  const groupLabels = new Map<string, string>()
  rfNodes.forEach(n => {
    if (n.type === 'groupNode') {
      groupLabels.set(n.id, ((n.data as Record<string, unknown>).label as string) || 'Group')
    }
  })

  const nodes: FlowGraphNode[] = rfNodes
    .filter(n => n.type !== 'groupNode')
    .map(n => {
      const nodeData = n.data as Record<string, unknown>
      // Prefer the (possibly edited) config carried on the node; fall back to
      // the original graph for nodes that never entered the editor's data.
      const config = {
        ...((nodeData.config as Record<string, unknown>) ?? configMap.get(n.id) ?? {}),
      }
      const editor = { ...((config._editor as Record<string, unknown>) || {}) }

      if (n.parentId && groupLabels.has(n.parentId)) {
        editor.group = { id: n.parentId, label: groupLabels.get(n.parentId) }
      } else {
        delete editor.group
      }

      if (Object.keys(editor).length > 0) {
        config._editor = editor
      } else {
        delete config._editor
      }

      return {
        id: n.id,
        type: ((n.data as Record<string, unknown>).type as string) || 'unknown',
        config,
      }
    })

  const edges = rfEdges.map(e => {
    const edge: { id: string; source: string; target: string; branch?: string } = {
      id: e.id,
      source: e.source,
      target: e.target,
    }
    if (e.sourceHandle) edge.branch = e.sourceHandle
    return edge
  })

  return { nodes, edges }
}
