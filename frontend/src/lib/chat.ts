export interface ToolActivity {
  tool: string
  status: 'running' | 'done'
  result?: string
}

export interface AgentActivityStep {
  nodeId: string
  nodeType: string
  label: string
  status: 'pending' | 'running' | 'completed' | 'failed'
  startedAt?: number
  completedAt?: number
}

export interface AgentActivity {
  instanceId: string
  status: 'working' | 'done' | 'failed'
  steps: AgentActivityStep[]
  startedAt: number
  durationMs?: number
}

export interface ChatMessage {
  id: string
  role: 'user' | 'ai'
  content: string
  timestamp: number
  tools?: ToolActivity[]
  activity?: AgentActivity
}

let nextId = 1

export function createMessage(role: ChatMessage['role'], content: string): ChatMessage {
  return {
    id: `msg-${nextId++}`,
    role,
    content,
    timestamp: Date.now(),
  }
}
