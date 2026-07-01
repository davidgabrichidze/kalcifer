const API_BASE = '/api/v1'

// ── Auth types ─────────────────────────────────────────

export interface AuthUser {
  id: string
  email: string
  name: string
  avatar_url: string | null
}

export interface AuthResponse {
  user: AuthUser
  token: string
  tenant_id: string
}

let _authToken: string | null = localStorage.getItem('kalcifer_token')

export function setAuthToken(token: string | null) {
  _authToken = token
  if (token) {
    localStorage.setItem('kalcifer_token', token)
  } else {
    localStorage.removeItem('kalcifer_token')
  }
}

export function getAuthToken(): string | null {
  return _authToken
}

/** Inject auth token into fetch requests */
function authHeaders(): Record<string, string> {
  if (_authToken) {
    return { Authorization: `Bearer ${_authToken}` }
  }
  return {}
}

export async function googleLogin(idToken: string): Promise<AuthResponse> {
  const res = await fetch(`${API_BASE}/auth/google`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ id_token: idToken }),
  })
  if (!res.ok) {
    const data = await res.json().catch(() => ({}))
    throw new Error(data.error || `HTTP ${res.status}`)
  }
  const data: AuthResponse = await res.json()
  setAuthToken(data.token)
  return data
}

export async function fetchMe(): Promise<AuthUser | null> {
  if (!_authToken) return null
  try {
    const res = await fetch(`${API_BASE}/auth/me`, {
      headers: authHeaders(),
    })
    if (!res.ok) return null
    const data = await res.json()
    return data.user
  } catch {
    return null
  }
}

export function logout() {
  setAuthToken(null)
  localStorage.removeItem('kalcifer_user')
}

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

export interface ChannelProvider {
  channel: string
  provider: string
  enabled: boolean
  configured: boolean
}

export interface Settings {
  ai_model: string
  ai_provider: string
  ai_api_key_set: boolean
  provider_keys: Record<string, boolean>
  available_models: ProviderGroup[]
  channel_providers?: ChannelProvider[]
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
  channel_provider?: { channel: string; provider: string; config?: Record<string, unknown>; enabled?: boolean }
  remove_channel_provider?: string
}): Promise<Settings> {
  const res = await fetch(`${API_BASE}/settings`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(params),
  })
  if (!res.ok) {
    const data = await res.json().catch(() => ({}))
    throw new Error(data.details?.settings?.[0] || data.message || `HTTP ${res.status}`)
  }
  return res.json()
}

export async function regenerateApiKey(): Promise<{ api_key: string; message: string }> {
  const res = await fetch(`${API_BASE}/settings/regenerate-api-key`, { method: 'POST' })
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  return res.json()
}

export async function fetchStats(): Promise<Stats> {
  const res = await fetch(`${API_BASE}/settings/stats`)
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  return res.json()
}

// ── Delivery types ───────────────────────────────────────

export interface DeliveryEntry {
  id: string
  channel: string
  status: 'pending' | 'sent' | 'delivered' | 'bounced' | 'failed'
  recipient: Record<string, string | null>
  provider: string | null
  provider_message_id: string | null
  error: string | null
  sent_at: string | null
  delivered_at: string | null
  failed_at: string | null
  inserted_at: string
}

export interface DeliveryStats {
  pending: number
  sent: number
  delivered: number
  bounced: number
  failed: number
}

export async function fetchDeliveries(opts?: {
  instance_id?: string
  status?: string
  limit?: number
}): Promise<DeliveryEntry[]> {
  const params = new URLSearchParams()
  if (opts?.instance_id) params.set('instance_id', opts.instance_id)
  if (opts?.status) params.set('status', opts.status)
  if (opts?.limit) params.set('limit', String(opts.limit))
  const qs = params.toString()
  const res = await fetch(`${API_BASE}/deliveries${qs ? `?${qs}` : ''}`)
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  const json = await res.json()
  return json.data
}

export async function fetchDeliveryStats(): Promise<DeliveryStats> {
  const res = await fetch(`${API_BASE}/deliveries/stats`)
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  const json = await res.json()
  return json.data
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

// ── Browse: Flows ───────────────────────────────────────

export interface Flow {
  id: string
  name: string
  description: string | null
  status: 'draft' | 'active' | 'paused' | 'archived'
  active_version_id: string | null
  entry_config: Record<string, unknown>
  exit_criteria: Record<string, unknown>
  frequency_cap: Record<string, unknown>
  inserted_at: string
  updated_at: string
}

export type FlowStatus = Flow['status']

export async function fetchFlows(status?: FlowStatus): Promise<Flow[]> {
  const params = status ? `?status=${status}` : ''
  const res = await fetch(`${API_BASE}/flows${params}`)
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  const json = await res.json()
  return json.data
}

export async function exportFlow(id: string): Promise<Record<string, unknown>> {
  const res = await fetch(`${API_BASE}/flows/${id}/export`)
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  return res.json()
}

export async function importFlow(data: {
  name?: string
  description?: string
  graph?: FlowGraph
  flow?: { name?: string; description?: string }
}): Promise<Flow> {
  const res = await fetch(`${API_BASE}/flows/import`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data),
  })
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  const json = await res.json()
  return json.data
}

export async function activateFlow(id: string): Promise<Flow> {
  const res = await fetch(`${API_BASE}/flows/${id}/activate`, { method: 'POST' })
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  const json = await res.json()
  return json.data
}

export async function pauseFlow(id: string): Promise<Flow> {
  const res = await fetch(`${API_BASE}/flows/${id}/pause`, { method: 'POST' })
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  const json = await res.json()
  return json.data
}

export async function archiveFlow(id: string): Promise<Flow> {
  const res = await fetch(`${API_BASE}/flows/${id}/archive`, { method: 'POST' })
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  const json = await res.json()
  return json.data
}

// ── Preflight / Validation ──────────────────────────────

export interface PreflightResult {
  warnings: string[]
  context_deps: string[]
  field_coverage?: Record<string, number>
  suggestions?: string[]
}

export async function preflightFlow(flowId: string): Promise<PreflightResult> {
  const res = await fetch(`${API_BASE}/flows/${flowId}/preflight`, { method: 'POST' })
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  const json = await res.json()
  return json.data
}

/**
 * Parse preflight warnings to extract per-node warnings.
 * Warning format: "node <node_id> (<node_type>): <message>"
 */
export function parseNodeWarnings(warnings: string[]): Map<string, string[]> {
  const map = new Map<string, string[]>()
  for (const w of warnings) {
    const match = w.match(/^node (\S+) \([^)]+\): (.+)$/)
    if (match) {
      const [, nodeId, message] = match
      const existing = map.get(nodeId!) || []
      existing.push(message!)
      map.set(nodeId!, existing)
    }
  }
  return map
}

// ── Chat types ──────────────────────────────────────────

export interface SessionClassification {
  kind: 'campaign' | 'flow' | 'analysis' | 'debug'
  title: string
  reason?: string
  flow_id?: string
}

export interface ChatStreamCallbacks {
  onInit?: (conversationId: string) => void
  onDelta: (text: string) => void
  onToolStart?: (tool: string, input: Record<string, unknown>) => void
  onToolDone?: (tool: string, result: string) => void
  onSessionClassified?: (classification: SessionClassification) => void
  onActivityStart?: (instanceId: string) => void
  onActivityStep?: (nodeId: string, nodeType: string, status: string) => void
  onActivityDone?: (status: string) => void
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
        let data: any
        try {
          data = JSON.parse(line.slice(6))
        } catch {
          console.warn('SSE: malformed JSON line, skipping:', line.slice(6, 100))
          continue
        }
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
          case 'activity_start':
            callbacks.onActivityStart?.(data.instance_id)
            break
          case 'activity_step':
            callbacks.onActivityStep?.(data.node_id, data.node_type, data.status)
            break
          case 'activity_done':
            callbacks.onActivityDone?.(data.status)
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

// ── Flow Editor API ─────────────────────────────────────

export interface FlowVersion {
  id: string
  version_number: number
  graph: FlowGraph
  status: 'draft' | 'published'
  changelog: string | null
  published_at: string | null
  inserted_at: string
  updated_at: string
}

export interface FlowGraph {
  nodes: FlowGraphNode[]
  edges: FlowGraphEdge[]
}

export interface FlowGraphNode {
  id: string
  type: string
  config: Record<string, unknown>
}

export interface FlowGraphEdge {
  source: string
  target: string
  branch?: string
}

export async function fetchFlow(id: string): Promise<Flow> {
  const res = await fetch(`${API_BASE}/flows/${id}`)
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  const json = await res.json()
  return json.data
}

export async function fetchFlowVersions(flowId: string): Promise<FlowVersion[]> {
  const res = await fetch(`${API_BASE}/flows/${flowId}/versions`)
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  const json = await res.json()
  return json.data
}

export async function fetchFlowVersion(
  flowId: string,
  versionNumber: number,
): Promise<FlowVersion> {
  const res = await fetch(`${API_BASE}/flows/${flowId}/versions/${versionNumber}`)
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  const json = await res.json()
  return json.data
}

// ── Simulation API ──────────────────────────────────────

export interface SimulationStep {
  step: number
  node_id: string
  node_type: string
  status: string
  result?: Record<string, unknown>
}

export interface SimulationCallbacks {
  onStart?: (data: { instance_id: string; flow_name: string; node_count: number }) => void
  onStep: (step: SimulationStep) => void
  onDone: (data: { status: string; step_count: number; duration_ms: number }) => void
  onError: (message: string) => void
}

export function simulateFlow(
  flowId: string,
  callbacks: SimulationCallbacks,
  opts?: { customer_id?: string; context?: Record<string, unknown> },
): AbortController {
  const controller = new AbortController()

  const body: Record<string, unknown> = {}
  if (opts?.customer_id) body.customer_id = opts.customer_id
  if (opts?.context) body.context = opts.context

  fetch(`${API_BASE}/flows/${flowId}/simulate`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
    signal: controller.signal,
  })
    .then(response => {
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      return readSimSSE(response, callbacks)
    })
    .catch(err => {
      if (err.name !== 'AbortError') {
        callbacks.onError(err.message)
      }
    })

  return controller
}

async function readSimSSE(response: Response, callbacks: SimulationCallbacks): Promise<void> {
  const reader = response.body?.getReader()
  if (!reader) { callbacks.onError('No response body'); return }

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
          case 'sim_start':
            callbacks.onStart?.(data)
            break
          case 'sim_step':
            callbacks.onStep(data)
            break
          case 'sim_done':
            callbacks.onDone(data)
            break
          case 'error':
            callbacks.onError(data.message)
            break
        }
      }
    }
  }
}

// ── Instance API ────────────────────────────────────────

export interface FlowInstanceSummary {
  id: string
  flow_id: string
  customer_id: string
  status: string
  version_number: number
  current_nodes: string[]
  dry_run: boolean
  entered_at: string
  completed_at: string | null
  exited_at: string | null
  exit_reason: string | null
}

export interface ExecutionStepData {
  id: string
  node_id: string
  node_type: string
  status: string
  started_at: string
  completed_at: string | null
  output: Record<string, unknown> | null
  error: Record<string, unknown> | null
}

export async function fetchInstances(
  flowId: string,
  opts?: { status?: string; dry_run?: boolean; limit?: number },
): Promise<FlowInstanceSummary[]> {
  const params = new URLSearchParams()
  if (opts?.status) params.set('status', opts.status)
  if (opts?.dry_run !== undefined) params.set('dry_run', String(opts.dry_run))
  if (opts?.limit) params.set('limit', String(opts.limit))
  const qs = params.toString()
  const res = await fetch(`${API_BASE}/flows/${flowId}/instances${qs ? `?${qs}` : ''}`)
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  const json = await res.json()
  return json.data
}

export async function fetchInstance(id: string): Promise<{
  data: FlowInstanceSummary
  steps: ExecutionStepData[]
}> {
  const res = await fetch(`${API_BASE}/instances/${id}`)
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  return res.json()
}

export async function fetchInstanceTimeline(id: string): Promise<ExecutionStepData[]> {
  const res = await fetch(`${API_BASE}/instances/${id}/timeline`)
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  const json = await res.json()
  return json.data
}

// ── Analytics API ───────────────────────────────────────

export interface NodeAnalytics {
  node_id: string
  executed: number
  completed: number
  failed: number
  avg_duration_ms?: number | null
}

export interface FlowSummaryStats {
  entered: number
  completed: number
  failed: number
  exited: number
  conversions: number
}

export async function fetchNodeAnalytics(
  flowId: string,
  opts?: { version?: number },
): Promise<NodeAnalytics[]> {
  const params = new URLSearchParams()
  if (opts?.version) params.set('version', String(opts.version))
  const qs = params.toString()
  const res = await fetch(`${API_BASE}/flows/${flowId}/analytics/nodes${qs ? `?${qs}` : ''}`)
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  const json = await res.json()
  return json.data
}

export async function fetchFlowSummary(flowId: string): Promise<FlowSummaryStats> {
  const res = await fetch(`${API_BASE}/flows/${flowId}/analytics/summary`)
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  const json = await res.json()
  return json.data
}

// ── Flow Version API ────────────────────────────────────

export async function updateFlowVersion(
  flowId: string,
  versionNumber: number,
  graph: FlowGraph,
): Promise<FlowVersion> {
  const res = await fetch(`${API_BASE}/flows/${flowId}/versions/${versionNumber}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ graph }),
  })
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  const json = await res.json()
  return json.data
}
