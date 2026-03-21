import { BrowserRouter, Routes, Route } from 'react-router-dom'
import { useTheme } from './lib/useTheme'
import TopBar from './components/TopBar'
import WorkPage from './pages/WorkPage'
import EditorPage from './pages/EditorPage'
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

        <Routes>
          <Route path="/" element={<WorkPage />} />
          <Route path="/editor" element={<EditorPage />} />
          <Route path="/engine" element={<EnginePage />} />
          <Route path="/browse" element={<BrowsePage />} />
        </Routes>
      </div>
    </BrowserRouter>
  )
}
