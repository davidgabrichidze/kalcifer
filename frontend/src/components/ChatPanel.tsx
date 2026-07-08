import { useState, useRef, useEffect, useCallback } from 'react'
import Markdown from 'react-markdown'
import { type ChatMessage, type ToolActivity, type AgentActivity, createMessage } from '../lib/chat'
import { streamChat, fetchConversation, type ApiMessage, type SessionClassification } from '../lib/api'
import { type ContextContent } from '../pages/WorkPage'
import { type Artifact } from './ArtifactPanel'
import ActivityIndicator from './ActivityIndicator'
import ToolBadges from './ToolBadges'
import ChatInput from './ChatInput'

const KIND_LABELS: Record<string, { label: string; icon: string }> = {
  campaign: { label: 'კამპანია', icon: '📣' },
  flow: { label: 'ფლოუ', icon: '⚡' },
  analysis: { label: 'ანალიზი', icon: '📊' },
  debug: { label: 'დიაგნოსტიკა', icon: '🔍' },
}

interface ChatPanelProps {
  placeholder?: string
  conversationId: string | null
  sessionKind: SessionClassification | null
  onConversationId?: (id: string) => void
  onSessionClassified?: (classification: SessionClassification) => void
  /** If set, send this text immediately on mount (used by welcome screen) */
  initialMessage?: string | null
  onInitialMessageSent?: () => void
  /** Called when a tool result contains content to display in the context area */
  onContextContent?: (content: ContextContent) => void
  /** Called when a new artifact is produced (flow created, analysis done, etc.) */
  onArtifact?: (artifact: Artifact) => void
  /** Called when the AI mutates a flow graph via a tool call */
  onFlowMutated?: (flowId: string) => void
}

export default function ChatPanel({
  placeholder = 'მიამბე რა გინდა გააკეთო...',
  conversationId,
  sessionKind,
  onConversationId,
  onSessionClassified,
  initialMessage,
  onInitialMessageSent,
  onContextContent,
  onArtifact,
  onFlowMutated,
}: ChatPanelProps) {
  const [messages, setMessages] = useState<ChatMessage[]>([])
  const [input, setInput] = useState('')
  const [isTyping, setIsTyping] = useState(false)
  const [_streamingId, setStreamingId] = useState<string | null>(null)
  const [activityExpanded, setActivityExpanded] = useState(false)
  const msgsEndRef = useRef<HTMLDivElement>(null)
  const abortRef = useRef<AbortController | null>(null)
  const activeAiIdRef = useRef<string | null>(null)
  const initialMessageSentRef = useRef(false)

  // Auto-scroll to bottom
  useEffect(() => {
    msgsEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages, isTyping])

  // Abort any in-flight stream when the panel unmounts, so a navigated-away
  // conversation doesn't keep an SSE fetch (and its callbacks) alive.
  useEffect(() => () => abortRef.current?.abort(), [])

  const appendToMessage = useCallback((id: string, text: string) => {
    setMessages(prev =>
      prev.map(m => (m.id === id ? { ...m, content: m.content + text } : m)),
    )
  }, [])

  const addToolToMessage = useCallback((id: string, tool: ToolActivity) => {
    setMessages(prev =>
      prev.map(m => {
        if (m.id !== id) return m
        const existing = m.tools ?? []
        // Update if same tool already exists (running → done)
        const idx = existing.findIndex(t => t.tool === tool.tool && t.status === 'running')
        if (idx >= 0 && tool.status === 'done') {
          const updated = [...existing]
          updated[idx] = tool
          return { ...m, tools: updated }
        }
        return { ...m, tools: [...existing, tool] }
      }),
    )
  }, [])

  const updateMessageActivity = useCallback((id: string, updater: (a: AgentActivity) => AgentActivity) => {
    setMessages(prev =>
      prev.map(m => {
        if (m.id !== id || !m.activity) return m
        return { ...m, activity: updater(m.activity) }
      }),
    )
  }, [])

  // Add a tool event to the currently running activity step
  const addToolToActivityStep = useCallback((msgId: string, tool: ToolActivity) => {
    updateMessageActivity(msgId, activity => {
      const runningIdx = activity.steps.findIndex(s => s.status === 'running')
      if (runningIdx < 0) return activity

      const step = activity.steps[runningIdx]!
      const existingTools = step.tools ?? []

      // Update existing running tool → done, or add new
      const idx = existingTools.findIndex(t => t.tool === tool.tool && t.status === 'running')
      let updatedTools: ToolActivity[]
      if (idx >= 0 && tool.status === 'done') {
        updatedTools = [...existingTools]
        updatedTools[idx] = tool
      } else {
        updatedTools = [...existingTools, tool]
      }

      const updatedSteps = [...activity.steps]
      updatedSteps[runningIdx] = { ...step, tools: updatedTools }
      return { ...activity, steps: updatedSteps }
    })
  }, [updateMessageActivity])

  // Activity callbacks factory for streamChat
  function activityCallbacks(aiMsgId: string) {
    return {
      onActivityStart: (instanceId: string) => {
        setMessages(prev =>
          prev.map(m =>
            m.id === aiMsgId
              ? { ...m, activity: { instanceId, status: 'working' as const, steps: [], startedAt: Date.now() } }
              : m,
          ),
        )
      },
      onActivityStep: (nodeId: string, nodeType: string, status: string) => {
        updateMessageActivity(aiMsgId, activity => {
          const existing = activity.steps.find(s => s.nodeId === nodeId)
          if (existing) {
            return {
              ...activity,
              steps: activity.steps.map(s =>
                s.nodeId === nodeId
                  ? { ...s, status: status as 'completed' | 'failed', completedAt: Date.now() }
                  : s,
              ),
            }
          }
          return {
            ...activity,
            steps: [
              ...activity.steps,
              { nodeId, nodeType, label: nodeType, status: 'running' as const, startedAt: Date.now() },
            ],
          }
        })
      },
      onActivityDone: (status: string) => {
        updateMessageActivity(aiMsgId, activity => ({
          ...activity,
          status: status === 'completed' ? 'done' as const : 'failed' as const,
          durationMs: Date.now() - activity.startedAt,
        }))
      },
    }
  }

  function handleSend() {
    const text = input.trim()
    if (!text || isTyping) return

    const userMsg = createMessage('user', text)
    const aiMsg = createMessage('ai', '')
    activeAiIdRef.current = aiMsg.id
    setMessages(prev => [...prev, userMsg, aiMsg])
    setInput('')
    setIsTyping(true)
    setStreamingId(aiMsg.id)

    // Capture the message ID so stale callbacks from aborted streams are ignored
    const msgId = aiMsg.id
    const isStale = () => activeAiIdRef.current !== msgId

    // Only send the new user message — backend loads history from conversation
    const apiMessages: ApiMessage[] = [{ role: 'user', content: text }]

    abortRef.current = streamChat(
      apiMessages,
      {
        onInit: (convId) => {
          if (isStale()) return
          loadedConvRef.current = convId
          onConversationId?.(convId)
        },
        onSessionClassified: (classification) => {
          if (isStale()) return
          onSessionClassified?.(classification)
        },
        onDelta: (chunk) => {
          if (isStale()) return
          appendToMessage(msgId, chunk)
        },
        onToolStart: (tool) => {
          if (isStale()) return
          addToolToMessage(msgId, { tool, status: 'running' })
          addToolToActivityStep(msgId, { tool, status: 'running' })
        },
        onToolDone: (tool, result) => {
          if (isStale()) return
          addToolToMessage(msgId, { tool, status: 'done', result })
          addToolToActivityStep(msgId, { tool, status: 'done', result })
          detectFlowGraph(tool, result)
        },
        ...activityCallbacks(msgId),
        onDone: () => {
          if (isStale()) return
          setIsTyping(false)
          setStreamingId(null)
          activeAiIdRef.current = null
        },
        onError: (msg) => {
          if (isStale()) return
          appendToMessage(msgId, `\n\n⚠ ${msg}`)
          setIsTyping(false)
          setStreamingId(null)
          activeAiIdRef.current = null
        },
      },
      conversationId ?? undefined,
    )
  }

  // Detect flow graph/flow_id in tool results and notify parent
  const FLOW_TOOLS = ['create_flow', 'get_flow_graph', 'add_node', 'modify_node', 'remove_node', 'get_flow']
  function detectFlowGraph(tool: string, result: string) {
    try {
      const parsed = JSON.parse(result)

      // Notify parent that the AI changed the graph so the editor can refresh
      const MUTATING_TOOLS = ['create_flow', 'add_node', 'modify_node', 'remove_node']
      const mutatedFlowId = tool === 'create_flow' ? parsed.id : parsed.flow_id
      if (MUTATING_TOOLS.includes(tool) && mutatedFlowId) {
        onFlowMutated?.(mutatedFlowId)
      }

      // Emit artifacts for the panel
      if (tool === 'create_flow' && parsed.id) {
        onArtifact?.({
          id: `flow-${parsed.id}`,
          type: 'flow',
          title: parsed.name || 'ახალი ფლოუ',
          subtitle: `${parsed.graph?.nodes?.length || 0} ნაბიჯი`,
          resourceId: parsed.id,
          data: parsed,
          timestamp: Date.now(),
        })
      } else if (tool === 'get_flow' && parsed.id) {
        onArtifact?.({
          id: `flow-${parsed.id}`,
          type: 'flow',
          title: parsed.name || 'ფლოუ',
          resourceId: parsed.id,
          data: parsed,
          timestamp: Date.now(),
        })
      } else if (['add_node', 'modify_node', 'remove_node'].includes(tool) && parsed.flow_id) {
        // No flow name in these results — keep the card's node count fresh
        // without stomping a nicer title an earlier create_flow/get_flow set.
        onArtifact?.({
          id: `flow-${parsed.flow_id}`,
          type: 'flow',
          title: 'ფლოუ',
          subtitle: typeof parsed.total_nodes === 'number' ? `${parsed.total_nodes} ნაბიჯი` : undefined,
          resourceId: parsed.flow_id,
          data: parsed,
          timestamp: Date.now(),
        })
      } else if (tool === 'analyze_flow') {
        onArtifact?.({
          id: `analysis-${Date.now()}`,
          type: 'analysis',
          title: parsed.flow_name || 'ანალიზი',
          subtitle: parsed.preflight?.valid ? '✓ ვალიდური' : '⚠ პრობლემები',
          data: parsed,
          timestamp: Date.now(),
        })
      } else if (tool === 'debug_instance' && parsed.instance_id) {
        onArtifact?.({
          id: `debug-${parsed.instance_id}`,
          type: 'debug',
          title: `Instance ${parsed.instance_id.slice(0, 8)}`,
          subtitle: parsed.status,
          resourceId: parsed.instance_id,
          data: parsed,
          timestamp: Date.now(),
        })
      } else if (tool === 'remember') {
        onArtifact?.({
          id: `memory-${Date.now()}`,
          type: 'memory',
          title: parsed.key || 'მეხსიერება',
          subtitle: 'დამახსოვრებულია',
          data: parsed,
          timestamp: Date.now(),
        })
      }
      // Opening the editor is the user's call — see the artifact card's own
      // click handler and the inline per-message card below. No auto-open here.
    } catch { /* not JSON, ignore */ }
  }

  // Send initial message from welcome screen (ref guard prevents StrictMode double-fire)
  useEffect(() => {
    if (initialMessage && !isTyping && messages.length === 0 && !initialMessageSentRef.current) {
      initialMessageSentRef.current = true
      const text = initialMessage
      onInitialMessageSent?.()

      const userMsg = createMessage('user', text)
      const aiMsg = createMessage('ai', '')
      const msgId = aiMsg.id
      activeAiIdRef.current = msgId
      setMessages([userMsg, aiMsg])
      setIsTyping(true)
      setStreamingId(msgId)

      const isStale = () => activeAiIdRef.current !== msgId
      const apiMessages: ApiMessage[] = [{ role: 'user', content: text }]
      abortRef.current = streamChat(
        apiMessages,
        {
          onInit: (convId) => {
            if (isStale()) return
            loadedConvRef.current = convId
            onConversationId?.(convId)
          },
          onSessionClassified: (classification) => {
            if (isStale()) return
            onSessionClassified?.(classification)
          },
          onDelta: (chunk) => {
            if (isStale()) return
            appendToMessage(msgId, chunk)
          },
          onToolStart: (tool) => {
            if (isStale()) return
            addToolToMessage(msgId, { tool, status: 'running' })
            addToolToActivityStep(msgId, { tool, status: 'running' })
          },
          onToolDone: (tool, result) => {
            if (isStale()) return
            addToolToMessage(msgId, { tool, status: 'done', result })
            addToolToActivityStep(msgId, { tool, status: 'done', result })
            detectFlowGraph(tool, result)
          },
          ...activityCallbacks(msgId),
          onDone: () => {
            if (isStale()) return
            setIsTyping(false)
            setStreamingId(null)
            activeAiIdRef.current = null
          },
          onError: (msg) => {
            if (isStale()) return
            appendToMessage(aiMsg.id, `\n\n⚠ ${msg}`)
            setIsTyping(false)
            setStreamingId(null)
            activeAiIdRef.current = null
          },
        },
        conversationId ?? undefined,
      )
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [initialMessage])

  // Load conversation history + cleanup — single effect to avoid race conditions
  const loadedConvRef = useRef<string | null>(null)
  useEffect(() => {
    // 0. Bail BEFORE aborting when the stream in flight is one we must not
    //    kill, otherwise the first reply of a new conversation is dropped:
    //    - initialMessage set: the initial-message effect owns the stream and
    //      runs on the same mount commit as this one.
    //    - id matches what we're already streaming into: our OWN onInit just
    //      assigned the new conversation its id.
    if (initialMessage) return
    if (conversationId && conversationId === loadedConvRef.current) return

    // 1. Abort any in-flight stream from a previous conversation
    if (abortRef.current) {
      abortRef.current.abort()
      abortRef.current = null
    }

    // 2. Reset streaming state
    setIsTyping(false)
    setStreamingId(null)
    activeAiIdRef.current = null
    setActivityExpanded(false)

    // 3. Handle no conversation (cleared)
    if (!conversationId) {
      if (!initialMessage) {
        loadedConvRef.current = null
        initialMessageSentRef.current = false
        setMessages([])
      }
      return
    }

    // 4. Skip if we're sending the initial message (its own effect streams it)
    if (initialMessage) return

    loadedConvRef.current = conversationId

    // 5. Load history from backend
    async function loadHistory() {
      try {
        const detail = await fetchConversation(conversationId!)
        // Guard: don't set messages if user already switched away
        if (loadedConvRef.current !== conversationId) return
        const loaded: ChatMessage[] = detail.messages.map(m =>
          createMessage(m.role === 'user' ? 'user' : 'ai', m.content),
        )
        setMessages(loaded)

        // Reopening a conversation already linked to a flow — show it as an
        // artifact card. Opening the editor stays the user's call (click the
        // card); the session_classified SSE event that would otherwise do
        // this only fires once, during classification, so a resumed
        // conversation needs its own way to surface the link.
        if (detail.entity_type === 'flow' && detail.entity_id) {
          onArtifact?.({
            id: `flow-${detail.entity_id}`,
            type: 'flow',
            title: 'ფლოუ',
            resourceId: detail.entity_id,
            timestamp: Date.now(),
          })
        }
      } catch {
        // Ignore — conversation might not exist yet
      }
    }
    loadHistory()
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [conversationId])

  const hasMessages = messages.length > 0
  const lastAIIndex = messages.findLastIndex(m => m.role === 'ai')

  return (
    <div
      className="flex flex-col"
      style={{ height: '100%', minHeight: 0, background: 'var(--color-bg)' }}
    >
      {/* Header with session kind badge */}
      {hasMessages && sessionKind && (
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: 6,
            padding: '8px 16px 0',
            flexShrink: 0,
            fontSize: 12.5,
            fontWeight: 600,
            color: 'var(--color-text)',
          }}
        >
          <span>{KIND_LABELS[sessionKind.kind]?.icon}</span>
          <span>{sessionKind.title}</span>
          <span
            style={{
              fontSize: 10,
              padding: '2px 6px',
              borderRadius: 6,
              background: 'var(--color-primary-soft)',
              color: 'var(--color-primary)',
            }}
          >
            {KIND_LABELS[sessionKind.kind]?.label}
          </span>
        </div>
      )}

      {/* Messages */}
      <div
        className="flex-1 overflow-y-auto"
        style={{ padding: '16px' }}
      >
        {messages.map((msg, msgIndex) => {
          const isUser = msg.role === 'user'
          const hasContent = msg.content.length > 0
          const hasTools = (msg.tools?.length ?? 0) > 0
          const isLastAI = msgIndex === lastAIIndex

          // Hide empty AI messages (typing indicator handles the visual)
          if (!isUser && !hasContent && !hasTools) return null

          return (
            <div
              key={msg.id}
              style={{
                display: 'flex',
                gap: 8,
                marginBottom: 16,
                alignItems: 'flex-start',
                flexDirection: isUser ? 'row-reverse' : 'row',
                animation: 'fadeUp 0.3s ease',
              }}
            >
              {/* Avatar */}
              <div
                style={{
                  width: 28,
                  height: 28,
                  borderRadius: '50%',
                  flexShrink: 0,
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  fontSize: isUser ? 9 : 11,
                  fontWeight: 600,
                  background: isUser
                    ? 'var(--color-accent)'
                    : 'var(--color-primary)',
                  color: 'var(--color-text-on-primary)',
                }}
              >
                {isUser ? 'DG' : 'K'}
              </div>

              {/* Body */}
              <div style={{ maxWidth: '82%', display: 'flex', flexDirection: 'column', gap: 6, minWidth: 0 }}>
                {/* Agent activity indicator */}
                {msg.activity && (
                  <ActivityIndicator
                    activity={msg.activity}
                    expanded={activityExpanded}
                    onToggle={() => setActivityExpanded(e => !e)}
                  />
                )}

                {/* Message bubble */}
                {(msg.content || isUser) && (
                  <div
                    className="chat-md"
                    style={{
                      padding: '11px 15px',
                      borderRadius: 14,
                      fontSize: 13.5,
                      lineHeight: 1.6,
                      whiteSpace: 'pre-wrap',
                      wordBreak: 'break-word',
                      ...(isUser
                        ? {
                            background: 'var(--color-primary-soft)',
                            border: '1px solid var(--color-primary-muted)',
                            color: 'var(--color-text)',
                          }
                        : {
                            background: 'var(--color-surface)',
                            border: '1px solid var(--color-border)',
                            color: 'var(--color-text)',
                          }),
                    }}
                  >
                    {isUser ? (
                      msg.content
                    ) : (
                      <Markdown>{msg.content}</Markdown>
                    )}
                  </div>
                )}

                {/* Tool badges — BELOW message text (spec: text → badges → artifacts → actions) */}
                {!msg.activity && msg.tools && msg.tools.length > 0 && (
                  <ToolBadges tools={msg.tools} />
                )}

                {/* Artifact card — inline flow/graph preview card (prototype style) */}
                {!isUser && msg.tools && (() => {
                  const flowTool = msg.tools.find(t =>
                    t.status === 'done' && FLOW_TOOLS.includes(t.tool) && t.result
                  )
                  if (!flowTool) return null
                  try {
                    const parsed = JSON.parse(flowTool.result!)
                    const flowId = parsed.id || parsed.flow_id
                    const title = parsed.name || (flowId ? 'Flow' : 'Graph')
                    const nodeCount = parsed.graph?.nodes?.length ?? 0
                    const edgeCount = parsed.graph?.edges?.length ?? 0
                    const subtitle = nodeCount > 0 ? `${nodeCount} node · ${edgeCount} edge · Draft` : undefined
                    const icon = '⚡'

                    const handleClick = () => {
                      if (flowId) {
                        onContextContent?.({ type: 'flow-editor', flowId })
                      } else if (parsed.graph?.nodes && parsed.graph?.edges) {
                        onContextContent?.({ type: 'flow-canvas', flowGraph: parsed.graph })
                      }
                    }

                    return (
                      <button
                        onClick={handleClick}
                        style={{
                          display: 'flex',
                          alignItems: 'center',
                          gap: 12,
                          padding: '10px 14px',
                          borderRadius: 12,
                          width: '100%',
                          background: 'var(--color-surface-raised)',
                          border: '1px solid var(--color-border)',
                          cursor: 'pointer',
                          textAlign: 'left',
                          fontFamily: 'inherit',
                          animation: 'fadeUp 0.4s ease 0.15s both',
                        }}
                      >
                        <span style={{
                          width: 38,
                          height: 38,
                          borderRadius: 10,
                          background: 'var(--color-primary-soft)',
                          border: '1px solid var(--color-primary-muted)',
                          display: 'flex',
                          alignItems: 'center',
                          justifyContent: 'center',
                          fontSize: 17,
                          flexShrink: 0,
                        }}>
                          {icon}
                        </span>
                        <div style={{ flex: 1, minWidth: 0 }}>
                          <div style={{ fontSize: 12.5, fontWeight: 600, color: 'var(--color-text)' }}>{title}</div>
                          {subtitle && <div style={{ fontSize: 10.5, color: 'var(--color-text-muted)', marginTop: 1 }}>{subtitle}</div>}
                        </div>
                        <span style={{
                          fontSize: 10,
                          fontWeight: 600,
                          color: 'var(--color-primary)',
                          padding: '5px 10px',
                          borderRadius: 8,
                          background: 'var(--color-primary-soft)',
                          border: '1px solid var(--color-primary-muted)',
                          whiteSpace: 'nowrap',
                          flexShrink: 0,
                        }}>
                          ⤢ გახსნა
                        </span>
                      </button>
                    )
                  } catch { return null }
                })()}

                {/* Quick actions — only on last AI message (prototype style: chip buttons) */}
                {isLastAI && !isUser && msg.quickActions && msg.quickActions.length > 0 && (
                  <div style={{ display: 'flex', flexWrap: 'wrap', gap: 5, animation: 'fadeUp 0.3s ease 0.25s both' }}>
                    {msg.quickActions.map((qa: { label: string }, i: number) => (
                      <button
                        key={i}
                        style={{
                          padding: '5px 12px',
                          borderRadius: 16,
                          background: 'var(--color-surface)',
                          border: '1px solid var(--color-border)',
                          color: 'var(--color-text-sec)',
                          fontSize: 11,
                          cursor: 'pointer',
                          fontFamily: 'inherit',
                        }}
                      >
                        {qa.label}
                      </button>
                    ))}
                  </div>
                )}
              </div>
            </div>
          )
        })}

        {/* Typing indicator — shown while waiting, hidden once content or tools arrive */}
        {isTyping && !messages.some(m => m.id === activeAiIdRef.current && (m.content.length > 0 || (m.tools?.length ?? 0) > 0 || m.activity)) && (
          <div
            style={{
              display: 'flex',
              gap: 8,
              marginBottom: 12,
              alignItems: 'flex-start',
              animation: 'fadeUp 0.3s ease',
            }}
          >
            <div
              style={{
                width: 28,
                height: 28,
                borderRadius: '50%',
                flexShrink: 0,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                fontSize: 11,
                fontWeight: 600,
                background: 'var(--color-primary)',
                color: 'var(--color-text-on-primary)',
              }}
            >
              K
            </div>
            <div
              style={{
                padding: '10px 14px',
                borderRadius: 14,
                background: 'var(--color-surface)',
                border: '1px solid var(--color-border)',
              }}
            >
              <div
                data-testid="typing-indicator"
                style={{ display: 'flex', gap: 3, padding: '3px 0' }}
              >
                <span
                  style={{
                    width: 5,
                    height: 5,
                    borderRadius: '50%',
                    background: 'var(--color-primary)',
                    animation: 'typingDot 1.2s infinite',
                  }}
                />
                <span
                  style={{
                    width: 5,
                    height: 5,
                    borderRadius: '50%',
                    background: 'var(--color-primary)',
                    animation: 'typingDot 1.2s infinite 0.2s',
                  }}
                />
                <span
                  style={{
                    width: 5,
                    height: 5,
                    borderRadius: '50%',
                    background: 'var(--color-primary)',
                    animation: 'typingDot 1.2s infinite 0.4s',
                  }}
                />
              </div>
            </div>
          </div>
        )}

        <div ref={msgsEndRef} />
      </div>

      {/* Input — extracted to ChatInput component */}
      <ChatInput
        value={input}
        onChange={setInput}
        onSend={handleSend}
        placeholder={placeholder}
        disabled={isTyping}
      />
    </div>
  )
}
