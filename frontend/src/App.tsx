import { useState, useEffect, useCallback } from 'react'
import { BrowserRouter, Routes, Route } from 'react-router-dom'
import { useTheme } from './lib/useTheme'
import TopBar from './components/TopBar'
import WorkPage from './pages/WorkPage'
import EnginePage from './pages/EnginePage'
import BrowsePage from './pages/BrowsePage'
import FlowEditorPage from './pages/editor/FlowEditorPage'
import LoginPage from './pages/LoginPage'
import { getAuthToken, logout, type AuthUser, type AuthResponse } from './lib/api'

export default function App() {
  const { theme, setTheme } = useTheme()
  const [user, setUser] = useState<AuthUser | null>(() => {
    try {
      const stored = localStorage.getItem('kalcifer_user')
      return stored ? JSON.parse(stored) : null
    } catch {
      return null
    }
  })

  // Check if we have a valid token on mount
  const [authChecked, setAuthChecked] = useState(false)

  useEffect(() => {
    const token = getAuthToken()
    if (!token) {
      setAuthChecked(true)
      return
    }
    // If we have a token + stored user, trust it (token is verified server-side)
    setAuthChecked(true)
  }, [])

  const handleLogin = useCallback((response: AuthResponse) => {
    setUser(response.user)
    localStorage.setItem('kalcifer_user', JSON.stringify(response.user))
  }, [])

  const handleLogout = useCallback(() => {
    logout()
    setUser(null)
  }, [])

  // Show login page if no auth (skip in dev if no Google client ID configured)
  const requireAuth = !!import.meta.env.VITE_GOOGLE_CLIENT_ID

  if (!authChecked) {
    return null // Loading
  }

  if (requireAuth && !user) {
    return <LoginPage onLogin={handleLogin} />
  }

  return (
    <BrowserRouter>
      <div
        className="flex h-screen flex-col"
        style={{ background: 'var(--color-bg)' }}
      >
        <TopBar
          theme={theme}
          onThemeChange={setTheme}
          user={user}
          onLogout={handleLogout}
        />

        <div className="relative flex flex-1 overflow-hidden">
          <Routes>
            <Route path="/" element={<WorkPage />} />
            <Route path="/engine" element={<EnginePage />} />
            <Route path="/browse" element={<BrowsePage />} />
            <Route path="/editor" element={<FlowEditorPage />} />
          </Routes>
        </div>
      </div>
    </BrowserRouter>
  )
}
