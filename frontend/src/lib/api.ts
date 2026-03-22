const API_BASE = '/api/v1'

// ── Conversation types ──────────────────────────────────

export interface Conversation {
  id: string
  title: string | null
  kind: string | null
  status: string
  inserted_at: string
  updated_at: string
}

export interface ConversationMessage {
  id: string
  role: 'user' | 'assistant'
  content: string
  inserted_at: string
}

export interface ConversationDetail extends Conversation {
  messages: ConversationMessage[]
}

// ── Conversation API ────────────────────────────────────

export async function fetchConversations(opts?: {
  kind?: string
  status?: string
}): Promise<Conversation[]> {
  const params = new URLSearchParams()
  if (opts?.kind) params.set('kind', opts.kind)
  if (opts?.status) params.set('status', opts.status)
  const url = `${API_BASE}/conversations${params.toString() ? '?' + params : ''}`
  const res = await fetch(url)
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  const data = await res.json()
  return data.conversations
}

export async function fetchConversation(id: string): Promise<ConversationDetail> {
  const res = await fetch(`${API_BASE}/conversations/${id}`)
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  const data = await res.json()
  return { ...data.conversation, messages: data.messages }
}

export async function renameConversation(id: string, title: string): Promise<Conversation> {
  const res = await fetch(`${API_BASE}/conversations/${id}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ title }),
  })
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  const data = await res.json()
  return data.conversation
}

export async function archiveConversation(id: string): Promise<Conversation> {
  const res = await fetch(`${API_BASE}/conversations/${id}/archive`, { method: 'POST' })
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  const data = await res.json()
  return data.conversation
}

export async function deleteConversation(id: string): Promise<void> {
  const res = await fetch(`${API_BASE}/conversations/${id}`, { method: 'DELETE' })
  if (!res.ok) {
    const data = await res.json().catch(() => ({}))
    throw new Error(data.error || `HTTP ${res.status}`)
  }
}

// ── Settings types ─────────────────────────────────────

export interface ModelOption {
  id: string
  name: string
}

export interface ProviderGroup {
  provider: string
  display_name: string
  models: ModelOption[]
}

export interface Settings {
  ai_model: string
  ai_provider: string
  ai_api_key_set: boolean
  provider_keys: Record<string, boolean>
  available_models: ProviderGroup[]
}

export interface Stats {
  conversations: { total: number; active: number }
  messages: { total: number }
  flows: { total: number; active: number }
  memories: { total: number }
}

// ── Settings API ──────────────────────────────────────

export async function fetchSettings(): Promise<Settings> {
  const res = await fetch(`${API_BASE}/settings`)
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  return res.json()
}

export async function updateSettings(params: {
  ai_model?: string
  ai_api_key?: string
  provider_key?: { provider: string; key: string }
  remove_provider_key?: string
}): Promise<Settings> {
  const res = await fetch(`${API_BASE}/settings`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(params),
  })
  if (!res.ok) {
    const data = await res.json().catch(() => ({}))
    throw new Error(data.errors?.settings?.[0] || `HTTP ${res.status}`)
  }
  return res.json()
}

export async function fetchStats(): Promise<Stats> {
  const res = await fetch(`${API_BASE}/settings/stats`)
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  return res.json()
}

// ── Engine types ─────────────────────────────────────────

export interface EngineNode {
  type: string
  module: string
  category: string
}

export interface EngineQueue {
  name: string
  concurrency: number
  executing: number
  available: number
  scheduled: number
  completed_24h: number
  failed_24h: number
}

export interface EngineData {
  node_registry: {
    total: number
    nodes: EngineNode[]
    categories: Record<string, number>
  }
  oban: {
    queues: EngineQueue[]
    total_concurrency: number
    total_completed_24h: number
    total_failed_24h: number
  }
  vm: {
    memory_total_mb: number
    memory_processes_mb: number
    memory_ets_mb: number
    process_count: number
    process_limit: number
    schedulers: number
    run_queue: number
    uptime_seconds: number
    otp_release: string
    elixir_version: string
  }
  db: {
    pool_size: number
    latency_ms: number
    adapter: string
  }
  instances: {
    running: number
    waiting: number
    total_active: number
  }
  logs: LogEntry[]
}

export interface LogEntry {
  level: string
  message: string
  timestamp: string
  source: string | null
  module: string | null
}

// ── Engine API ──────────────────────────────────────────

export async function fetchEngine(): Promise<EngineData> {
  const res = await fetch(`${API_BASE}/engine`)
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  return res.json()
}

// ── Chat types ──────────────────────────────────────────

export interface SessionClassification {
  kind: 'campaign' | 'flow' | 'analysis' | 'debug'
  title: string
  reason?: string
}

export interface ChatStreamCallbacks {
  onInit?: (conversationId: string) => void
  onDelta: (text: string) => void
  onToolStart?: (tool: string, input: Record<string, unknown>) => void
  onToolDone?: (tool: string, result: string) => void
  onSessionClassified?: (classification: SessionClassification) => void
  onDone: (fullText: string) => void
  onError: (message: string) => void
}

export interface ApiMessage {
  role: 'user' | 'assistant'
  content: string
}

/**
 * Streams a chat response from the backend via SSE.
 * Returns an AbortController so the caller can cancel.
 */
export function streamChat(
  messages: ApiMessage[],
  callbacks: ChatStreamCallbacks,
  conversationId?: string,
): AbortController {
  const controller = new AbortController()

  const body: Record<string, unknown> = { messages }
  if (conversationId) {
    body.conversation_id = conversationId
  }

  fetch(`${API_BASE}/chat`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
    signal: controller.signal,
  })
    .then(response => {
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`)
      }
      return readSSEStream(response, callbacks)
    })
    .catch(err => {
      if (err.name !== 'AbortError') {
        callbacks.onError(err.message)
      }
    })

  return controller
}

async function readSSEStream(
  response: Response,
  callbacks: ChatStreamCallbacks,
): Promise<void> {
  const reader = response.body?.getReader()
  if (!reader) {
    callbacks.onError('No response body')
    return
  }

  const decoder = new TextDecoder()
  let buffer = ''

  while (true) {
    const { done, value } = await reader.read()
    if (done) break

    buffer += decoder.decode(value, { stream: true })
    const lines = buffer.split('\n')
    buffer = lines.pop() ?? ''

    let currentEvent = ''
    for (const line of lines) {
      if (line.startsWith('event: ')) {
        currentEvent = line.slice(7)
      } else if (line.startsWith('data: ')) {
        const data = JSON.parse(line.slice(6))
        switch (currentEvent) {
          case 'init':
            callbacks.onInit?.(data.conversation_id)
            break
          case 'delta':
            callbacks.onDelta(data.text)
            break
          case 'tool_start':
            callbacks.onToolStart?.(data.tool, data.input)
            break
          case 'tool_done':
            callbacks.onToolDone?.(data.tool, data.result)
            break
          case 'session_classified':
            callbacks.onSessionClassified?.(data)
            break
          case 'done':
            callbacks.onDone(data.text)
            break
          case 'error':
            callbacks.onError(data.message)
            break
        }
      }
    }
  }
}
