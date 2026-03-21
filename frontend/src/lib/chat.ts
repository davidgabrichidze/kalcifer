export interface ChatMessage {
  id: string
  role: 'user' | 'ai'
  content: string
  timestamp: number
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
