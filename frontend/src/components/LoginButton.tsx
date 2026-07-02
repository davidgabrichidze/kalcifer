import { useCallback, useEffect, useRef } from 'react'
import { googleLogin, type AuthResponse } from '../lib/api'

declare global {
  interface Window {
    google?: {
      accounts: {
        id: {
          initialize: (config: Record<string, unknown>) => void
          renderButton: (element: HTMLElement, config: Record<string, unknown>) => void
          prompt: () => void
        }
      }
    }
  }
}

interface LoginButtonProps {
  onLogin: (response: AuthResponse) => void
  onError?: (error: string) => void
}

/**
 * Google Sign-In button component.
 * Loads the Google Identity Services library and renders the sign-in button.
 */
export default function LoginButton({ onLogin, onError }: LoginButtonProps) {
  const buttonRef = useRef<HTMLDivElement>(null)
  const initializedRef = useRef(false)

  const handleCredentialResponse = useCallback(
    async (response: { credential: string }) => {
      try {
        const authResponse = await googleLogin(response.credential)
        // Store user info
        localStorage.setItem('kalcifer_user', JSON.stringify(authResponse.user))
        onLogin(authResponse)
      } catch (e) {
        onError?.(e instanceof Error ? e.message : 'Login failed')
      }
    },
    [onLogin, onError],
  )

  useEffect(() => {
    if (initializedRef.current) return
    initializedRef.current = true

    const clientId = import.meta.env.VITE_GOOGLE_CLIENT_ID

    if (!clientId) {
      console.warn('VITE_GOOGLE_CLIENT_ID not set — Google login disabled')
      return
    }

    // Load Google Identity Services script
    const script = document.createElement('script')
    script.src = 'https://accounts.google.com/gsi/client'
    script.async = true
    script.defer = true
    script.onload = () => {
      if (!window.google || !buttonRef.current) return

      window.google.accounts.id.initialize({
        client_id: clientId,
        callback: handleCredentialResponse,
      })

      window.google.accounts.id.renderButton(buttonRef.current, {
        theme: 'outline',
        size: 'large',
        text: 'signin_with',
        shape: 'rectangular',
        logo_alignment: 'center',
        width: 280,
      })
    }
    document.head.appendChild(script)

    return () => {
      // Cleanup script if component unmounts
      if (script.parentNode) {
        script.parentNode.removeChild(script)
      }
    }
  }, [handleCredentialResponse])

  return (
    <div>
      <div ref={buttonRef} style={{ minHeight: 44 }} />
      {!import.meta.env.VITE_GOOGLE_CLIENT_ID && (
        <div
          style={{
            padding: '10px 16px',
            background: 'var(--color-warn-soft)',
            color: 'var(--color-warn)',
            borderRadius: 8,
            fontSize: 11,
            textAlign: 'center',
          }}
        >
          VITE_GOOGLE_CLIENT_ID არ არის კონფიგურირებული
        </div>
      )}
    </div>
  )
}
