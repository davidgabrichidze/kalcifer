import { BrowserRouter, Routes, Route, NavLink } from 'react-router-dom'
import { useTheme } from './lib/useTheme'
import TopBar from './components/TopBar'
import WorkPage from './pages/WorkPage'
import EnginePage from './pages/EnginePage'
import BrowsePage from './pages/BrowsePage'

export default function App() {
  const { theme, setTheme } = useTheme()

  return (
    <BrowserRouter>
      <div
        className="flex h-screen flex-col"
        style={{ background: 'var(--color-bg)' }}
      >
        <TopBar theme={theme} onThemeChange={setTheme} />

        <div className="relative flex flex-1 overflow-hidden">
          <Routes>
            <Route path="/" element={<WorkPage />} />
            <Route path="/engine" element={<EnginePage />} />
            <Route path="/browse" element={<BrowsePage />} />
          </Routes>

          {/* Engine Room — secondary nav, bottom-left */}
          <NavLink
            to="/engine"
            title="Engine Room"
            className="absolute bottom-4 left-4"
            style={({ isActive }) => ({
              width: 36,
              height: 36,
              borderRadius: 10,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              fontSize: 16,
              cursor: 'pointer',
              transition: 'all 0.2s',
              border: isActive
                ? '1px solid var(--color-primary)'
                : '1px solid var(--color-border)',
              background: isActive
                ? 'var(--color-primary-soft)'
                : 'var(--color-surface)',
              color: isActive
                ? 'var(--color-primary)'
                : 'var(--color-text-muted)',
              boxShadow: 'var(--shadow-sm)',
            })}
          >
            ⚙
          </NavLink>
        </div>
      </div>
    </BrowserRouter>
  )
}
