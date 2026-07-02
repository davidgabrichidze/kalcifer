import { useEffect, useRef, useState, useCallback } from 'react'
import { Channel, Presence, Socket } from 'phoenix'

export interface FlowEvent {
  type: string
  payload: Record<string, unknown>
  timestamp: string
}

interface UseFlowSocketOptions {
  /** flow ID to subscribe to */
  flowId: string | null
  /** Whether the socket should be active */
  enabled?: boolean
  /** Callback for each incoming event */
  onEvent?: (event: FlowEvent) => void
}

const SOCKET_URL = `${window.location.protocol === 'https:' ? 'wss:' : 'ws:'}//${window.location.host}/socket`

/**
 * Hook to connect to a Phoenix Channel for real-time flow events.
 *
 * Subscribes to `flow:{flowId}` topic and forwards engine events
 * (instance_started, node_executed, instance_completed, etc.)
 */
export function useFlowSocket({ flowId, enabled = true, onEvent }: UseFlowSocketOptions) {
  const socketRef = useRef<Socket | null>(null)
  const channelRef = useRef<Channel | null>(null)
  const [connected, setConnected] = useState(false)
  const [operators, setOperators] = useState<Array<{ id: string; name: string }>>([])
  const [activeInstances, setActiveInstances] = useState<Set<string>>(new Set())
  const [completedNodes, setCompletedNodes] = useState<Map<string, Set<string>>>(new Map())
  const [activeNodes, setActiveNodes] = useState<Map<string, string | null>>(new Map())
  const [failedNodes, setFailedNodes] = useState<Set<string>>(new Set())

  const onEventRef = useRef(onEvent)
  useEffect(() => {
    onEventRef.current = onEvent
  }, [onEvent])

  const processEvent = useCallback((type: string, msg: { payload: Record<string, unknown>; timestamp: string }) => {
    const event: FlowEvent = { type, payload: msg.payload, timestamp: msg.timestamp }
    onEventRef.current?.(event)

    const instanceId = msg.payload.instance_id as string | undefined

    switch (type) {
      case 'instance_started':
        if (instanceId) {
          setActiveInstances(prev => new Set([...prev, instanceId]))
        }
        break

      case 'node_executed':
        if (instanceId && msg.payload.node_id) {
          const nodeId = msg.payload.node_id as string
          const status = msg.payload.status as string | undefined

          if (status === 'failed') {
            setFailedNodes(prev => new Set([...prev, nodeId]))
          } else {
            setCompletedNodes(prev => {
              const next = new Map(prev)
              const nodes = new Set(next.get(instanceId) || [])
              nodes.add(nodeId)
              next.set(instanceId, nodes)
              return next
            })
          }
          setActiveNodes(prev => {
            const next = new Map(prev)
            next.set(instanceId, null)
            return next
          })
        }
        break

      case 'node_waiting':
        if (instanceId && msg.payload.node_id) {
          setActiveNodes(prev => {
            const next = new Map(prev)
            next.set(instanceId, msg.payload.node_id as string)
            return next
          })
        }
        break

      case 'instance_completed':
      case 'instance_failed':
        if (instanceId) {
          setActiveInstances(prev => {
            const next = new Set(prev)
            next.delete(instanceId)
            return next
          })
          setActiveNodes(prev => {
            const next = new Map(prev)
            next.delete(instanceId)
            return next
          })
        }
        break
    }
  }, [])

  useEffect(() => {
    if (!flowId || !enabled) {
      // Cleanup if disabled
      channelRef.current?.leave()
      channelRef.current = null
      socketRef.current?.disconnect()
      socketRef.current = null
      setConnected(false)
      return
    }

    // Connect socket
    const socket = new Socket(SOCKET_URL, {
      params: { api_key: 'demo-dev-key' },
    })
    socket.connect()
    socketRef.current = socket

    // Join flow channel with a per-tab operator identity for presence
    const operatorId = `op-${Math.random().toString(36).slice(2, 10)}`
    const channel = socket.channel(`flow:${flowId}`, {
      operator_id: operatorId,
      operator_name: 'Operator',
    })
    channelRef.current = channel

    // Track who else is viewing this flow
    const presence = new Presence(channel)
    presence.onSync(() => {
      const list = presence.list((id, entry) => ({
        id,
        name: entry.metas[0]?.name || 'Operator',
      }))
      setOperators(list)
    })

    // Listen for all engine events
    const eventTypes = [
      'instance_started',
      'instance_completed',
      'instance_failed',
      'node_executed',
      'node_waiting',
      'node_resumed',
    ]

    for (const eventType of eventTypes) {
      channel.on(eventType, (msg: Record<string, unknown>) =>
        processEvent(eventType, msg as { payload: Record<string, unknown>; timestamp: string }),
      )
    }

    channel.join()
      .receive('ok', () => setConnected(true))
      .receive('error', (resp: unknown) => {
        console.error('Failed to join flow channel:', resp)
        setConnected(false)
      })

    return () => {
      channel.leave()
      socket.disconnect()
      setConnected(false)
      setOperators([])
    }
  }, [flowId, enabled, processEvent])

  const clearState = useCallback(() => {
    setActiveInstances(new Set())
    setCompletedNodes(new Map())
    setActiveNodes(new Map())
    setFailedNodes(new Set())
  }, [])

  return {
    connected,
    operators,
    activeInstances,
    completedNodes,
    activeNodes,
    failedNodes,
    clearState,
  }
}
