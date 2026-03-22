const API_BASE = '/api/v1'

export interface ChatStreamCallbacks {
  onInit?: (conversationId: string) => void
  onDelta: (text: string) => void
  onToolStart?: (tool: string, input: Record<string, unknown>) => void
  onToolDone?: (tool: string, result: string) => void
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
