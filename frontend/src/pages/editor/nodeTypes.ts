/**
 * Node type metadata for the flow editor.
 * Categories: trigger, condition, wait, action, end
 * Icons are single characters/emoji for display in node badges.
 */

export type NodeCategory = 'trigger' | 'condition' | 'wait' | 'action' | 'end'

export interface NodeTypeMetadata {
  key: string
  category: NodeCategory
  label: string
  icon: string
  description: string
}

export const NODE_TYPES: Record<string, NodeTypeMetadata> = {
  // Triggers
  segment_entry: {
    key: 'segment_entry',
    category: 'trigger',
    label: 'Segment Entry',
    icon: 'T',
    description: 'Trigger when user enters segment',
  },
  event_entry: {
    key: 'event_entry',
    category: 'trigger',
    label: 'Event Entry',
    icon: 'T',
    description: 'Trigger on custom event',
  },
  webhook_entry: {
    key: 'webhook_entry',
    category: 'trigger',
    label: 'Webhook Entry',
    icon: 'T',
    description: 'Trigger from external webhook',
  },

  // Conditions
  condition: {
    key: 'condition',
    category: 'condition',
    label: 'Condition',
    icon: '?',
    description: 'Branch by expression',
  },
  ab_split: {
    key: 'ab_split',
    category: 'condition',
    label: 'A/B Split',
    icon: 'AB',
    description: 'Random split for testing',
  },
  frequency_cap: {
    key: 'frequency_cap',
    category: 'condition',
    label: 'Frequency Cap',
    icon: '#',
    description: 'Limit message frequency',
  },
  check_segment: {
    key: 'check_segment',
    category: 'condition',
    label: 'Check Segment',
    icon: 'S',
    description: 'Branch by segment membership',
  },

  // Waits
  wait: {
    key: 'wait',
    category: 'wait',
    label: 'Wait',
    icon: 'W',
    description: 'Delay for duration (e.g. "2d")',
  },
  wait_for_event: {
    key: 'wait_for_event',
    category: 'wait',
    label: 'Wait for Event',
    icon: 'W',
    description: 'Wait until event fires',
  },
  wait_until: {
    key: 'wait_until',
    category: 'wait',
    label: 'Wait Until',
    icon: 'W',
    description: 'Wait until specific time',
  },

  // Actions - Channel
  send_email: {
    key: 'send_email',
    category: 'action',
    label: 'Send Email',
    icon: '✉',
    description: 'SendGrid, Mailgun...',
  },
  send_sms: {
    key: 'send_sms',
    category: 'action',
    label: 'Send SMS',
    icon: '☎',
    description: 'Twilio, Vonage...',
  },
  send_push: {
    key: 'send_push',
    category: 'action',
    label: 'Send Push',
    icon: '🔔',
    description: 'Firebase FCM',
  },
  send_whatsapp: {
    key: 'send_whatsapp',
    category: 'action',
    label: 'Send WhatsApp',
    icon: 'W',
    description: 'Twilio WhatsApp',
  },
  send_in_app: {
    key: 'send_in_app',
    category: 'action',
    label: 'In-App Message',
    icon: '◻',
    description: 'via WebSocket',
  },

  // Actions - Data
  call_webhook: {
    key: 'call_webhook',
    category: 'action',
    label: 'Call Webhook',
    icon: '{}',
    description: 'HTTP POST to external',
  },
  track_conversion: {
    key: 'track_conversion',
    category: 'action',
    label: 'Track Conversion',
    icon: '$',
    description: 'Record conversion event',
  },
  add_tag: {
    key: 'add_tag',
    category: 'action',
    label: 'Add Tag',
    icon: '#',
    description: 'Tag profile for segmentation',
  },
  update_profile: {
    key: 'update_profile',
    category: 'action',
    label: 'Update Profile',
    icon: '✎',
    description: 'Modify user data',
  },

  // Conditions (advanced)
  preference_gate: {
    key: 'preference_gate',
    category: 'condition',
    label: 'Preference Gate',
    icon: '⚙',
    description: 'Check user preference opt-in',
  },
  ai_decide: {
    key: 'ai_decide',
    category: 'condition',
    label: 'AI Decide',
    icon: '✦',
    description: 'AI-powered branching logic',
  },

  // Actions - Data (advanced)
  custom_code: {
    key: 'custom_code',
    category: 'action',
    label: 'Custom Code',
    icon: '</>',
    description: 'Run custom logic',
  },
  memory_recall: {
    key: 'memory_recall',
    category: 'action',
    label: 'Memory Recall',
    icon: '🧠',
    description: 'Recall operator memories into context',
  },

  // Actions - AI
  ai_think: {
    key: 'ai_think',
    category: 'action',
    label: 'AI Think',
    icon: '✦',
    description: 'AI text generation with flow context',
  },
  ai_notify: {
    key: 'ai_notify',
    category: 'action',
    label: 'AI Notify',
    icon: '📣',
    description: 'Notify operators (PubSub)',
  },
  agent: {
    key: 'agent',
    category: 'action',
    label: 'Agent',
    icon: '🤖',
    description: 'Multi-round AI agent with tools',
  },
  flow_router: {
    key: 'flow_router',
    category: 'condition',
    label: 'Flow Router',
    icon: '⇶',
    description: 'AI picks a route to a sub-flow',
  },

  // Orchestration
  parallel_group: {
    key: 'parallel_group',
    category: 'action',
    label: 'Parallel Group',
    icon: '≡',
    description: 'Run branches in parallel',
  },
  sub_flow: {
    key: 'sub_flow',
    category: 'action',
    label: 'Sub-Flow',
    icon: '▣',
    description: 'Run another flow as a child',
  },

  // End
  exit: {
    key: 'exit',
    category: 'end',
    label: 'Exit',
    icon: '✓',
    description: 'Complete flow instance',
  },
  goal_reached: {
    key: 'goal_reached',
    category: 'end',
    label: 'Goal Reached',
    icon: '🏁',
    description: 'Complete flow and record conversion',
  },
}

export function getNodeType(key: string): NodeTypeMetadata | undefined {
  return NODE_TYPES[key]
}

export function getNodesByCategory(category: NodeCategory): NodeTypeMetadata[] {
  return Object.values(NODE_TYPES).filter(nt => nt.category === category)
}
