declare module 'phoenix' {
  export class Socket {
    constructor(endPoint: string, opts?: Record<string, unknown>)
    connect(): void
    disconnect(): void
    channel(topic: string, params?: Record<string, unknown>): Channel
  }

  export class Channel {
    join(): Push
    leave(): Push
    on(event: string, callback: (msg: Record<string, unknown>) => void): number
    push(event: string, payload: Record<string, unknown>): Push
  }

  export class Push {
    receive(status: string, callback: (response: unknown) => void): Push
  }

  export interface PresenceMeta {
    phx_ref: string
    name?: string
    online_at?: string
    [key: string]: unknown
  }

  export interface PresenceEntry {
    metas: PresenceMeta[]
  }

  export class Presence {
    constructor(channel: Channel, opts?: Record<string, unknown>)
    onSync(callback: () => void): void
    list<T>(chooser: (id: string, entry: PresenceEntry) => T): T[]
  }
}
