/// <reference types="vite/client" />

interface ImportMetaEnv {
  /** Google OAuth client id; when unset, auth is disabled. */
  readonly VITE_GOOGLE_CLIENT_ID?: string
  /** Phoenix socket auth key (hashed to a tenant server-side). */
  readonly VITE_SOCKET_API_KEY?: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
