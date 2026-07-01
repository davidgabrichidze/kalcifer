import { describe, expect, it } from 'vitest'
import { NODE_TYPES, getNodesByCategory } from './nodeTypes'

// Keep in sync with lib/kalcifer/engine/node_registry.ex @built_in_nodes
const BACKEND_NODE_TYPES = [
  'event_entry',
  'segment_entry',
  'webhook_entry',
  'send_email',
  'send_sms',
  'send_push',
  'send_whatsapp',
  'call_webhook',
  'wait',
  'wait_until',
  'wait_for_event',
  'condition',
  'ab_split',
  'frequency_cap',
  'update_profile',
  'add_tag',
  'custom_code',
  'exit',
  'goal_reached',
  'send_in_app',
  'check_segment',
  'preference_gate',
  'track_conversion',
  'ai_think',
  'ai_decide',
  'ai_notify',
  'agent',
  'parallel_group',
  'sub_flow',
  'flow_router',
  'memory_recall',
]

describe('NODE_TYPES palette', () => {
  it('covers every backend built-in node type', () => {
    const missing = BACKEND_NODE_TYPES.filter(key => !NODE_TYPES[key])
    expect(missing).toEqual([])
  })

  it('has no palette entries unknown to the backend', () => {
    const extra = Object.keys(NODE_TYPES).filter(key => !BACKEND_NODE_TYPES.includes(key))
    expect(extra).toEqual([])
  })

  it('keys match their metadata key field', () => {
    for (const [key, meta] of Object.entries(NODE_TYPES)) {
      expect(meta.key).toBe(key)
    }
  })

  it('end category contains exit and goal_reached', () => {
    const keys = getNodesByCategory('end').map(nt => nt.key)
    expect(keys.sort()).toEqual(['exit', 'goal_reached'])
  })
})
