import { BrowserRouter, Routes, Route } from 'react-router-dom'
import { useTheme } from './lib/useTheme'
import TopBar from './components/TopBar'
import WorkPage from './pages/WorkPage'
import EnginePage from './pages/EnginePage'
import BrowsePage from './pages/BrowsePage'
import FlowEditorPage from './pages/editor/FlowEditorPage'

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
            <Route path="/editor" element={<FlowEditorPage />} />
          </Routes>
        </div>
      </div>
    </BrowserRouter>
  )
}
