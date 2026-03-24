import { useState } from 'react'
import LoginButton from '../components/LoginButton'
import { type AuthResponse } from '../lib/api'

interface LoginPageProps {
  onLogin: (response: AuthResponse) => void
}

export default function LoginPage({ onLogin }: LoginPageProps) {
  const [error, setError] = useState<string | null>(null)

  return (
    <div
      style={{
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        height: '100vh',
        background: 'var(--color-bg)',
      }}
    >
      <div
        style={{
          textAlign: 'center',
          padding: 40,
          background: 'var(--color-surface)',
          border: '1px solid var(--color-border)',
          borderRadius: 16,
          maxWidth: 380,
          width: '100%',
        }}
      >
        {/* Logo */}
        <div
          style={{
            fontSize: 36,
            fontWeight: 700,
            color: 'var(--color-primary)',
            marginBottom: 4,
          }}
        >
          K
          <span style={{ fontSize: 18, fontWeight: 400, color: 'var(--color-text-muted)', marginLeft: 2 }}>
            alcifer
          </span>
        </div>
        <div
          style={{
            fontSize: 12,
            color: 'var(--color-text-muted)',
            marginBottom: 32,
          }}
        >
          Flow Orchestration Engine
        </div>

        {/* Google Sign-In */}
        <div style={{ display: 'flex', justifyContent: 'center', marginBottom: 16 }}>
          <LoginButton onLogin={onLogin} onError={setError} />
        </div>

        {error && (
          <div
            style={{
              padding: '8px 12px',
              background: 'var(--color-danger-soft)',
              color: 'var(--color-danger)',
              borderRadius: 8,
              fontSize: 11,
              marginTop: 8,
            }}
          >
            {error}
          </div>
        )}
      </div>
    </div>
  )
}
