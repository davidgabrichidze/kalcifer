import { useState, useCallback, useRef, useEffect, useMemo } from "react"

// ═══════════════════════════════════════════════════════════════════
// Kalcifer — Work Page Prototype v4
//
// Right panel = Cowork-style contextual container:
//   sidebar mode: Todo/Progress + Artifacts + Context
//   editor mode: artifact viewer/editor (replaces sidebar content)
//
// Chat area = messages only (tool badges, inline artifacts, quick actions)
// ═══════════════════════════════════════════════════════════════════

const C = {
  bg: "#161210", surface: "#1e1a16", surfaceDim: "#1a1612", surfaceRaised: "#282220",
  primary: "#e0a060", primaryHover: "#e8b070", primarySoft: "rgba(224,160,96,0.10)",
  primaryMuted: "rgba(224,160,96,0.22)", accent: "#c090d0", accentSoft: "rgba(192,144,208,0.10)",
  border: "#302a24", borderLight: "#282220", text: "#e8ddd0", textSec: "#b8a898",
  textMuted: "#786858", textOnPrimary: "#161210", success: "#6cc480",
  successSoft: "rgba(108,196,128,0.10)", warn: "#e0b860", warnSoft: "rgba(224,184,96,0.10)",
  danger: "#e07060", dangerSoft: "rgba(224,112,96,0.10)", info: "#70a8e0",
  infoSoft: "rgba(112,168,224,0.10)",
}
const EASE = "cubic-bezier(0.4, 0, 0.2, 1)"

// ═══════════════════════════════════════
// Data
// ═══════════════════════════════════════

const KIND_META = {
  campaign: { icon: "📣", label: "კამპანიები", color: C.primary },
  flow: { icon: "⚡", label: "ფლოუები", color: C.info },
  analysis: { icon: "📊", label: "ანალიზი", color: C.accent },
  debug: { icon: "🔍", label: "დიაგნოსტიკა", color: C.warn },
}

const SESSIONS = [
  { id: "s1", title: "Welcome კამპანია", kind: "campaign", status: "done", updatedAt: "5 წთ წინ", unread: true },
  { id: "s2", title: "Churn re-engagement", kind: "flow", status: "thinking", updatedAt: "2 სთ წინ", unread: false },
  { id: "s3", title: "Email conversion rates", kind: "analysis", status: "done", updatedAt: "1 დღის წინ", unread: false },
  { id: "s4", title: "Instance #a8f3 debug", kind: "debug", status: "idle", updatedAt: "3 დღის წინ", unread: false },
]

const STATUS_INDICATOR = {
  thinking: { color: C.warn, pulse: true },
  done: { color: C.success, pulse: false },
  idle: { color: C.textMuted, pulse: false },
  error: { color: C.danger, pulse: false },
}

const DEMO_MESSAGES = [
  { id: "m1", role: "user", content: "Welcome კამპანია გავაკეთოთ — ახალი მომხმარებლები რომ დარეგისტრირდებიან, მისალმების email გავუგზავნოთ, 3 დღეში follow-up." },
  { id: "m2", role: "ai",
    content: "გავაკეთე Welcome კამპანიის flow. სტრუქტურა ასეთია:\n\n**Event Entry** → user_registered ტრიგერზე ეშვება\n**Send Email** → მისალმების email, subject: \"მოგესალმებით! 👋\"\n**Wait 3d** → 3 დღე ელოდება\n**Send Email** → follow-up, subject: \"როგორ მოგეწონათ? 🤔\"\n**End** → flow სრულდება",
    tools: [
      { name: "create_flow", label: "ფლოუს შექმნა", status: "done" },
      { name: "add_node", label: "5 ნაბიჯის დამატება", status: "done" },
    ],
    artifact: { id: "flow-welcome", type: "flow", title: "Welcome კამპანია", subtitle: "5 node · 4 edge · Draft", icon: "⚡" },
    quickActions: [{ label: "გავააქტიურო?" }, { label: "Dry Run" }, { label: "სრულ ედიტორში" }],
  },
  { id: "m3", role: "user", content: "პირველ email-ში emoji დაამატე subject-ში და body-ში CTA ღილაკი იყოს." },
  { id: "m4", role: "ai", content: "შევცვალე — subject ახლა \"მოგესალმებით! 👋\" და body-ში CTA ღილაკი დავამატე \"შემოგვიერთდი →\" ტექსტით.",
    tools: [{ name: "modify_node", label: "ნაბიჯის შეცვლა", status: "done" }] },
  { id: "m5", role: "user", content: "კარგია. wait-ის ნაცვლად 2 დღე იყოს — 3 ბევრია." },
  { id: "m6", role: "ai", content: "შევცვალე — Wait ახლა 2 დღეა, არა 3. Canvas განახლდა.",
    tools: [{ name: "modify_node", label: "ნაბიჯის შეცვლა", status: "done" }],
    quickActions: [{ label: "გავააქტიურო?" }, { label: "Dry Run" }] },
]

const DEMO_PROGRESS = [
  { id: "a1", label: "ფლოუს შექმნა", status: "done", detail: "Welcome კამპანია" },
  { id: "a2", label: "Event Entry დამატება", status: "done", detail: "user_registered" },
  { id: "a3", label: "Send Email დამატება", status: "done", detail: "მოგესალმებით! 👋" },
  { id: "a4", label: "Wait დამატება", status: "done", detail: "3 დღე" },
  { id: "a5", label: "Send Email დამატება", status: "done", detail: "როგორ მოგეწონათ?" },
  { id: "a6", label: "End დამატება", status: "done" },
]

const DEMO_CONTEXT = [
  { label: "Flow Engine", type: "skill", detail: "create_flow, add_node, modify_node" },
  { label: "Email Channel", type: "skill", detail: "send_email, template builder" },
  { label: "სესიის ტიპი", type: "meta", detail: "კამპანია" },
]

const FLOW_NODES = [
  { id: "n1", type: "trigger", label: "Event Entry", sub: "event_entry", detail: "user_registered", color: C.info, icon: "T" },
  { id: "n2", type: "action", label: "Send Email", sub: "send_email", detail: "მოგესალმებით! 👋", color: C.primary, icon: "✉" },
  { id: "n3", type: "wait", label: "Wait", sub: "wait", detail: "2d", color: C.accent, icon: "W" },
  { id: "n4", type: "action", label: "Send Email", sub: "send_email", detail: "როგორ მოგეწონათ? 🤔", color: C.primary, icon: "✉" },
  { id: "n5", type: "end", label: "End", sub: "end", detail: "", color: C.success, icon: "✓" },
]

const WELCOME_HINTS = [
  { label: "Welcome კამპანია", text: "Welcome კამპანია გავაკეთოთ — ახალი მომხმარებლები რომ დარეგისტრირდებიან, მისალმების email გავუგზავნოთ, 3 დღეში follow-up." },
  { label: "Churn re-engagement", text: "90 დღე არააქტიურ მომხმარებლებს re-engagement flow გავუკეთო" },
  { label: "A/B ტესტი", text: "A/B ტესტი email subject-ებისთვის — რომელი უკეთ მუშაობს?" },
  { label: "რა nodes არსებობს?", text: "რა ტიპის nodes არსებობს სისტემაში?" },
]

// ═══════════════════════════════════════
// Main App
// ═══════════════════════════════════════

export default function KalciferWork() {
  const [stage, setStage] = useState("welcome")
  const [sidebarMode, setSidebarMode] = useState("hidden")
  const [activeSessionId, setActiveSessionId] = useState(null)
  const [messages, setMessages] = useState([])
  const [inputVal, setInputVal] = useState("")
  const [isTyping, setIsTyping] = useState(false)
  const [sessionTitle, setSessionTitle] = useState("")

  // Right panel: "hidden" | "sidebar" | "editor"
  const [rightMode, setRightMode] = useState("hidden")
  const [progressSteps, setProgressSteps] = useState([])
  const [progressExpanded, setProgressExpanded] = useState(false)
  const [artifactsExpanded, setArtifactsExpanded] = useState(true)
  const [contextExpanded, setContextExpanded] = useState(false)

  const chatEndRef = useRef(null)
  const demoTimersRef = useRef([])

  useEffect(() => () => demoTimersRef.current.forEach(clearTimeout), [])
  useEffect(() => { chatEndRef.current?.scrollIntoView({ behavior: "smooth" }) }, [messages, isTyping])

  useEffect(() => {
    if (stage === "welcome") setSidebarMode("hidden")
    else if (stage === "lobby" || stage === "chat") setSidebarMode("expanded")
    else if (stage === "split" || stage === "context") setSidebarMode("collapsed")
  }, [stage])

  const artifacts = useMemo(() => messages.filter(m => m.artifact).map(m => m.artifact), [messages])
  const clearDemo = useCallback(() => { demoTimersRef.current.forEach(clearTimeout); demoTimersRef.current = [] }, [])
  const addTimer = useCallback((fn, ms) => { const t = setTimeout(fn, ms); demoTimersRef.current.push(t); return t }, [])

  const reset = useCallback(() => {
    clearDemo(); setStage("welcome"); setMessages([]); setActiveSessionId(null)
    setIsTyping(false); setRightMode("hidden"); setInputVal(""); setSessionTitle("")
    setProgressSteps([]); setProgressExpanded(false); setArtifactsExpanded(true); setContextExpanded(false)
  }, [clearDemo])

  // Open editor mode in right panel
  const openEditor = useCallback(() => {
    setRightMode("editor")
    setStage(s => s === "chat" ? "split" : s)
  }, [])

  // Back to sidebar mode (from editor)
  const backToSidebar = useCallback(() => {
    setRightMode("sidebar")
    if (stage === "context") setStage("chat")
    else if (stage === "split") setStage("chat")
  }, [stage])

  // Close right panel entirely
  const closeRightPanel = useCallback(() => {
    setRightMode("hidden")
    setStage(s => (s === "split" || s === "context") ? "chat" : s)
  }, [])

  const toggleExpand = useCallback(() => { setStage(s => s === "split" ? "context" : "split") }, [])
  const toggleSidebar = useCallback(() => { setSidebarMode(m => m === "expanded" ? "collapsed" : "expanded") }, [])

  // Demo
  const runDemo = useCallback(() => {
    clearDemo(); setActiveSessionId("s1"); setStage("chat"); setMessages([])
    setSessionTitle("Welcome კამპანია"); setRightMode("sidebar")
    setProgressSteps([]); setProgressExpanded(false); setArtifactsExpanded(true); setContextExpanded(false)

    addTimer(() => { setMessages([DEMO_MESSAGES[0]]); setIsTyping(true) }, 300)

    // AI starts working — progress appears in right sidebar
    addTimer(() => {
      setProgressSteps([{ ...DEMO_PROGRESS[0], status: "running" }])
      setProgressExpanded(true)
      setMessages([DEMO_MESSAGES[0], { ...DEMO_MESSAGES[1], content: "", tools: [{ name: "create_flow", label: "ფლოუს შექმნა", status: "running" }] }])
    }, 1200)

    addTimer(() => {
      setProgressSteps(DEMO_PROGRESS.slice(0, 3).map((s, i) => ({ ...s, status: i < 2 ? "done" : "running" })))
      setMessages([DEMO_MESSAGES[0], { ...DEMO_MESSAGES[1], content: "", tools: [
        { name: "create_flow", label: "ფლოუს შექმნა", status: "done" },
        { name: "add_node", label: "5 ნაბიჯის დამატება", status: "running" },
      ]}])
    }, 2200)

    addTimer(() => { setProgressSteps(DEMO_PROGRESS.map(s => ({ ...s, status: "done" }))) }, 3000)

    // AI done — progress auto-collapses
    addTimer(() => { setIsTyping(false); setMessages(DEMO_MESSAGES.slice(0, 2)); setProgressExpanded(false) }, 3500)

    // User clicks artifact → right panel switches to editor, stage → split
    addTimer(() => { setRightMode("editor"); setStage("split") }, 5500)

    // Conversation continues
    addTimer(() => { setMessages(DEMO_MESSAGES.slice(0, 3)); setIsTyping(true) }, 7500)
    addTimer(() => { setIsTyping(false); setMessages(DEMO_MESSAGES.slice(0, 4)) }, 9000)
    addTimer(() => { setMessages(DEMO_MESSAGES.slice(0, 5)); setIsTyping(true) }, 11500)
    addTimer(() => { setIsTyping(false); setMessages(DEMO_MESSAGES.slice(0, 6)) }, 13000)
  }, [clearDemo, addTimer])

  const handleSend = useCallback(() => {
    if (!inputVal.trim()) return; setInputVal("")
    if (stage === "welcome" || stage === "lobby") runDemo()
  }, [inputVal, stage, runDemo])

  const handleHintClick = useCallback((hint) => { setInputVal(hint.text); setTimeout(() => runDemo(), 100) }, [runDemo])

  useEffect(() => {
    const h = (e) => { if ((e.metaKey || e.ctrlKey) && e.key === "\\") { e.preventDefault(); toggleSidebar() } }
    window.addEventListener("keydown", h); return () => window.removeEventListener("keydown", h)
  }, [toggleSidebar])

  const sidebarWidth = sidebarMode === "hidden" ? 0 : sidebarMode === "collapsed" ? 52 : 210
  const showRight = rightMode !== "hidden"
  const isEditor = rightMode === "editor"

  return (
    <div style={{ height: "100vh", display: "flex", flexDirection: "column", background: C.bg, color: C.text, fontFamily: "'Inter', -apple-system, sans-serif", overflow: "hidden" }}>
      <Styles />

      {/* TopBar */}
      <header style={{ height: 48, flexShrink: 0, background: C.surface, borderBottom: `1px solid ${C.border}`, display: "flex", alignItems: "center", justifyContent: "space-between", padding: "0 16px" }}>
        <span style={{ fontSize: 17, fontWeight: 700, color: C.primary, letterSpacing: -0.5, cursor: "pointer" }} onClick={reset}>Kalcifer</span>
        <nav style={{ display: "flex", gap: 4 }}>
          {[{ l: "Work", active: true }, { l: "Browse" }, { l: "Engine Room" }].map(n => (
            <button key={n.l} style={{ height: 30, padding: "0 12px", borderRadius: 6, fontSize: 11, fontWeight: 500, fontFamily: "inherit", cursor: "pointer", border: n.active ? `1px solid ${C.primary}` : `1px solid ${C.border}`, background: n.active ? C.primary : C.surfaceDim, color: n.active ? C.textOnPrimary : C.textSec }}>{n.l}</button>
          ))}
        </nav>
        <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
          <div style={{ display: "flex", gap: 2, background: C.surfaceRaised, borderRadius: 6, padding: 2 }}>
            {["welcome", "chat", "split", "context"].map(s => (
              <button key={s} onClick={() => {
                if (s === "welcome") reset()
                else {
                  if (!messages.length) { setMessages(DEMO_MESSAGES); setActiveSessionId("s1"); setSessionTitle("Welcome კამპანია"); setProgressSteps(DEMO_PROGRESS) }
                  setStage(s)
                  if (s === "chat") setRightMode("sidebar")
                  else if (s === "split" || s === "context") setRightMode("editor")
                }
              }} style={{ padding: "3px 8px", borderRadius: 4, border: "none", fontSize: 9, fontWeight: 600, fontFamily: "inherit", cursor: "pointer", textTransform: "uppercase", letterSpacing: 0.3, background: stage === s ? C.primary : "transparent", color: stage === s ? C.textOnPrimary : C.textMuted }}>{s}</button>
            ))}
          </div>
          <div style={{ width: 28, height: 28, borderRadius: "50%", background: C.primary, color: C.textOnPrimary, display: "flex", alignItems: "center", justifyContent: "center", fontSize: 10, fontWeight: 600 }}>DG</div>
        </div>
      </header>

      {/* Main */}
      <div style={{ flex: 1, display: "flex", overflow: "hidden", minHeight: 0 }}>

        <Sidebar mode={sidebarMode} width={sidebarWidth} sessions={SESSIONS} activeId={activeSessionId}
          onSelect={(id) => { setActiveSessionId(id); if (stage === "welcome") runDemo() }}
          onNewSession={() => { if (stage === "welcome") return; clearDemo(); setStage("lobby"); setActiveSessionId(null); setMessages([]); setRightMode("hidden"); setSessionTitle(""); setProgressSteps([]) }}
          onToggle={toggleSidebar} />

        {/* Chat (Center) */}
        <div style={{
          flex: isEditor && showRight ? (stage === "context" ? "0 0 340px" : "0 0 440px") : "1",
          display: "flex", flexDirection: "column",
          minWidth: 0, overflow: "hidden",
          borderRight: showRight ? `1px solid ${C.border}` : "none",
          transition: `flex 0.5s ${EASE}, border 0.3s`,
          background: C.bg,
        }}>
          {(stage === "chat" || stage === "split" || stage === "context") && sessionTitle && (
            <div style={{ display: "flex", alignItems: "center", gap: 6, padding: "8px 16px", flexShrink: 0, borderBottom: `1px solid ${C.border}`, background: C.surface }}>
              <span style={{ fontSize: 13 }}>📣</span>
              <span style={{ fontSize: 13, fontWeight: 600 }}>{sessionTitle}</span>
              <span style={{ fontSize: 9.5, padding: "2px 7px", borderRadius: 6, background: C.primarySoft, color: C.primary, fontWeight: 600 }}>კამპანია</span>
            </div>
          )}

          {(stage === "welcome" || stage === "lobby") && <WelcomeScreen hints={WELCOME_HINTS} onHintClick={handleHintClick} showSubtitle={stage === "lobby"} />}

          {(stage === "chat" || stage === "split" || stage === "context") && (
            <div style={{ flex: 1, overflow: "auto", padding: "16px 16px 8px" }} className="chat-scroll">
              {messages.map(msg => <ChatMessage key={msg.id} msg={msg} onOpenArtifact={openEditor} compact={stage === "context"} />)}
              {isTyping && <TypingIndicator />}
              <div ref={chatEndRef} />
            </div>
          )}

          <ChatInput value={inputVal} onChange={setInputVal} onSend={handleSend}
            placeholder={stage === "welcome" || stage === "lobby" ? "მიამბე რა გინდა გააკეთო..." : "შეტყობინება..."} />
        </div>

        {/* Right Panel — sidebar or editor */}
        {showRight && (
          <RightPanel
            mode={rightMode} stage={stage}
            progressSteps={progressSteps}
            progressExpanded={progressExpanded} onToggleProgress={() => setProgressExpanded(p => !p)}
            artifacts={artifacts}
            artifactsExpanded={artifactsExpanded} onToggleArtifacts={() => setArtifactsExpanded(a => !a)}
            contextItems={DEMO_CONTEXT}
            contextExpanded={contextExpanded} onToggleContext={() => setContextExpanded(c => !c)}
            onArtifactClick={openEditor}
            nodes={FLOW_NODES} editorTitle="Welcome კამპანია"
            onBackToSidebar={backToSidebar}
            onClose={closeRightPanel}
            onToggleExpand={toggleExpand}
          />
        )}
      </div>
    </div>
  )
}

// ═══════════════════════════════════════
// Right Panel — Cowork-style contextual container
// ═══════════════════════════════════════

function RightPanel({
  mode, stage,
  progressSteps, progressExpanded, onToggleProgress,
  artifacts, artifactsExpanded, onToggleArtifacts,
  contextItems, contextExpanded, onToggleContext,
  onArtifactClick,
  nodes, editorTitle, onBackToSidebar, onClose, onToggleExpand,
}) {
  const isSidebar = mode === "sidebar"
  const isEditor = mode === "editor"

  return (
    <div style={{
      flex: isEditor ? (stage === "context" ? 3 : 1) : "0 0 300px",
      display: "flex", flexDirection: "column",
      overflow: "hidden", background: C.bg,
      borderLeft: isSidebar ? `1px solid ${C.border}` : "none",
      animation: "slideIn 0.4s cubic-bezier(0.4, 0, 0.2, 1)",
      transition: `flex 0.5s ${EASE}`,
    }}>
      {isSidebar ? (
        <SidebarContent
          progressSteps={progressSteps} progressExpanded={progressExpanded} onToggleProgress={onToggleProgress}
          artifacts={artifacts} artifactsExpanded={artifactsExpanded} onToggleArtifacts={onToggleArtifacts}
          contextItems={contextItems} contextExpanded={contextExpanded} onToggleContext={onToggleContext}
          onArtifactClick={onArtifactClick}
        />
      ) : (
        <EditorContent
          stage={stage} nodes={nodes} title={editorTitle}
          onBack={onBackToSidebar} onClose={onClose} onToggleExpand={onToggleExpand}
        />
      )}
    </div>
  )
}

// ── Sidebar Mode ──
function SidebarContent({
  progressSteps, progressExpanded, onToggleProgress,
  artifacts, artifactsExpanded, onToggleArtifacts,
  contextItems, contextExpanded, onToggleContext,
  onArtifactClick,
}) {
  const doneCount = progressSteps.filter(s => s.status === "done").length
  const isRunning = progressSteps.some(s => s.status === "running")

  return (
    <div style={{ flex: 1, overflow: "auto", display: "flex", flexDirection: "column" }} className="chat-scroll">
      {/* Progress / Todo */}
      {progressSteps.length > 0 && (
        <CollapsibleSection
          title={isRunning ? "მიმდინარეობს..." : `${doneCount}/${progressSteps.length} შესრულდა`}
          icon={<span style={{ width: 6, height: 6, borderRadius: "50%", background: isRunning ? C.warn : C.success, animation: isRunning ? "pulse 1.2s infinite" : "none" }} />}
          expanded={progressExpanded}
          onToggle={onToggleProgress}
        >
          <div style={{ display: "flex", flexDirection: "column", gap: 1, padding: "0 14px 10px" }}>
            {progressSteps.map((step, i) => (
              <div key={step.id} style={{ display: "flex", alignItems: "center", gap: 8, padding: "4px 0", animation: `fadeUp 0.2s ease ${i * 0.04}s both` }}>
                <span style={{
                  width: 16, height: 16, borderRadius: "50%", flexShrink: 0,
                  display: "flex", alignItems: "center", justifyContent: "center", fontSize: 8,
                  background: step.status === "done" ? C.successSoft : C.warnSoft,
                  color: step.status === "done" ? C.success : C.warn,
                }}>{step.status === "done" ? "✓" : "•"}</span>
                <span style={{ fontSize: 11, color: step.status === "done" ? C.textSec : C.text, flex: 1 }}>{step.label}</span>
                {step.detail && <span style={{ fontSize: 10, color: C.textMuted, fontFamily: "monospace" }}>{step.detail}</span>}
              </div>
            ))}
          </div>
        </CollapsibleSection>
      )}

      {/* Artifacts (Working) */}
      {artifacts.length > 0 && (
        <CollapsibleSection
          title={`${artifacts.length} არტეფაქტი`}
          icon={<span style={{ fontSize: 11 }}>📎</span>}
          expanded={artifactsExpanded}
          onToggle={onToggleArtifacts}
        >
          <div style={{ padding: "0 10px 10px" }}>
            {artifacts.map((art, i) => (
              <button key={art.id} onClick={onArtifactClick} className="artifact-card" style={{
                display: "flex", alignItems: "center", gap: 8, width: "100%",
                padding: "8px 10px", borderRadius: 10,
                background: C.surfaceRaised, border: `1px solid ${C.border}`,
                cursor: "pointer", textAlign: "left", fontFamily: "inherit",
                marginBottom: 4, transition: "all 0.2s",
                animation: `fadeUp 0.3s ease ${i * 0.08}s both`,
              }}>
                <span style={{
                  width: 32, height: 32, borderRadius: 8,
                  background: C.primarySoft, border: `1px solid ${C.primaryMuted}`,
                  display: "flex", alignItems: "center", justifyContent: "center",
                  fontSize: 15, flexShrink: 0,
                }}>{art.icon}</span>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: 11.5, fontWeight: 600, color: C.text, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{art.title}</div>
                  <div style={{ fontSize: 9.5, color: C.textMuted, marginTop: 1 }}>{art.subtitle}</div>
                </div>
                <span style={{ fontSize: 10, color: C.primary, fontWeight: 600, flexShrink: 0 }}>→</span>
              </button>
            ))}
          </div>
        </CollapsibleSection>
      )}

      {/* Context / Skills */}
      {contextItems && contextItems.length > 0 && (
        <CollapsibleSection
          title="კონტექსტი"
          icon={<span style={{ fontSize: 11 }}>🧩</span>}
          expanded={contextExpanded}
          onToggle={onToggleContext}
        >
          <div style={{ padding: "0 14px 10px", display: "flex", flexDirection: "column", gap: 4 }}>
            {contextItems.map((item, i) => (
              <div key={i} style={{ display: "flex", alignItems: "flex-start", gap: 8, padding: "4px 0" }}>
                <span style={{
                  fontSize: 8, padding: "2px 6px", borderRadius: 4, fontWeight: 600, flexShrink: 0, marginTop: 2,
                  background: item.type === "skill" ? C.infoSoft : C.accentSoft,
                  color: item.type === "skill" ? C.info : C.accent,
                  border: `1px solid ${item.type === "skill" ? "rgba(112,168,224,0.15)" : "rgba(192,144,208,0.15)"}`,
                }}>{item.type === "skill" ? "SKILL" : "META"}</span>
                <div>
                  <div style={{ fontSize: 11, fontWeight: 600, color: C.text }}>{item.label}</div>
                  <div style={{ fontSize: 10, color: C.textMuted }}>{item.detail}</div>
                </div>
              </div>
            ))}
          </div>
        </CollapsibleSection>
      )}
    </div>
  )
}

function CollapsibleSection({ title, icon, expanded, onToggle, children }) {
  return (
    <div style={{ borderBottom: `1px solid ${C.border}` }}>
      <button onClick={onToggle} style={{
        width: "100%", display: "flex", alignItems: "center", gap: 8,
        padding: "10px 14px", border: "none", background: "transparent",
        cursor: "pointer", fontFamily: "inherit", textAlign: "left",
      }}>
        {icon}
        <span style={{ fontSize: 11.5, fontWeight: 600, color: C.text, flex: 1 }}>{title}</span>
        <span style={{ fontSize: 9, color: C.textMuted, transform: expanded ? "rotate(180deg)" : "none", transition: "transform 0.2s" }}>▼</span>
      </button>
      {expanded && children}
    </div>
  )
}

// ── Editor Mode ──
function EditorContent({ stage, nodes, title, onBack, onClose, onToggleExpand }) {
  return (
    <>
      {/* Header */}
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", padding: "8px 14px", flexShrink: 0, borderBottom: `1px solid ${C.border}`, background: C.surface }}>
        <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
          <PanelBtn onClick={onBack} small>←</PanelBtn>
          <span style={{ fontSize: 14 }}>⚡</span>
          <span style={{ fontSize: 13, fontWeight: 600 }}>{title}</span>
          <span style={{ fontSize: 9.5, padding: "2px 8px", borderRadius: 8, background: C.infoSoft, color: C.info, fontWeight: 600 }}>Draft</span>
          <span style={{ fontSize: 10, color: C.textMuted, fontFamily: "monospace" }}>v1</span>
        </div>
        <div style={{ display: "flex", gap: 4 }}>
          <PanelBtn onClick={onToggleExpand}>{stage === "split" ? "⤢" : "⤡"}</PanelBtn>
          <PanelBtn onClick={onClose}>✕</PanelBtn>
        </div>
      </div>

      {/* Editor mode tabs */}
      <div style={{ display: "flex", gap: 4, padding: "8px 14px", borderBottom: `1px solid ${C.border}`, background: C.surface }}>
        {[{ l: "✎ Edit", active: true }, { l: "▶ Simulate" }, { l: "◉ Live" }].map(m => (
          <button key={m.l} style={{
            height: 26, padding: "0 10px", borderRadius: 5, fontSize: 10.5, fontWeight: 500, fontFamily: "inherit", cursor: "pointer",
            border: m.active ? `1px solid ${C.primary}` : `1px solid ${C.border}`,
            background: m.active ? C.primary : C.surfaceDim, color: m.active ? C.textOnPrimary : C.textSec,
          }}>{m.l}</button>
        ))}
      </div>

      {/* Flow canvas */}
      <div style={{ flex: 1, display: "flex", flexDirection: "column", alignItems: "center", padding: "28px 20px", overflow: "auto" }} className="chat-scroll">
        {nodes.map((node, i) => (
          <div key={node.id}>
            <div className="flow-node" style={{
              width: stage === "context" ? 260 : 220, padding: "12px 16px",
              background: C.surface, border: `1.5px solid ${node.color}`,
              borderRadius: 12, cursor: "pointer", transition: "all 0.3s",
              animation: `fadeUp 0.4s ease ${i * 0.08}s both`,
            }}>
              <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: node.detail ? 6 : 0 }}>
                <span style={{ width: 26, height: 26, borderRadius: 7, background: `${node.color}18`, color: node.color, display: "flex", alignItems: "center", justifyContent: "center", fontSize: 10, fontWeight: 700, flexShrink: 0, border: `1px solid ${node.color}30` }}>{node.icon}</span>
                <div>
                  <div style={{ fontSize: 12.5, fontWeight: 600, color: C.text }}>{node.label}</div>
                  <div style={{ fontSize: 9, color: C.textMuted, fontFamily: "monospace" }}>{node.sub}</div>
                </div>
              </div>
              {node.detail && <div style={{ fontSize: 11, color: C.textSec, paddingLeft: 34 }}>{node.detail}</div>}
            </div>
            {i < nodes.length - 1 && (
              <div style={{ display: "flex", flexDirection: "column", alignItems: "center", height: 28 }}>
                <div style={{ width: 2, flex: 1, background: C.border }} />
                <div style={{ width: 6, height: 6, borderRadius: "50%", background: C.border, margin: "2px 0" }} />
              </div>
            )}
          </div>
        ))}
      </div>

      {/* Bottom bar */}
      <div style={{ height: 36, flexShrink: 0, background: C.surface, borderTop: `1px solid ${C.border}`, display: "flex", alignItems: "center", justifyContent: "space-between", padding: "0 14px", fontSize: 10, color: C.textMuted }}>
        <div style={{ display: "flex", gap: 12 }}>
          <span style={{ display: "flex", alignItems: "center", gap: 4 }}><span style={{ width: 5, height: 5, borderRadius: "50%", background: C.success }} /><strong style={{ color: C.textSec }}>{nodes.length}</strong> nodes</span>
          <span style={{ display: "flex", alignItems: "center", gap: 4 }}><span style={{ width: 5, height: 5, borderRadius: "50%", background: C.info }} /><strong style={{ color: C.textSec }}>{nodes.length - 1}</strong> edges</span>
        </div>
        <span style={{ fontFamily: "monospace", padding: "2px 8px", background: C.surfaceDim, borderRadius: 4 }}>Ready</span>
      </div>
    </>
  )
}

// ═══════════════════════════════════════
// Sidebar, WelcomeScreen, ChatMessage, etc.
// ═══════════════════════════════════════

function Sidebar({ mode, width, sessions, activeId, onSelect, onNewSession, onToggle }) {
  const isCollapsed = mode === "collapsed"
  if (mode === "hidden") return null
  const groups = useMemo(() => { const m = new Map(); sessions.forEach(s => { const l = m.get(s.kind) ?? []; l.push(s); m.set(s.kind, l) }); return m }, [sessions])

  return (
    <div style={{ width, minWidth: width, maxWidth: width, background: C.surface, borderRight: `1px solid ${C.border}`, display: "flex", flexDirection: "column", transition: `all 0.35s ${EASE}`, overflow: "hidden" }}>
      <div style={{ padding: isCollapsed ? "10px 7px 4px" : "10px 10px 4px", flexShrink: 0 }}>
        {isCollapsed ? (
          <button onClick={onToggle} style={{ width: 38, height: 38, borderRadius: 10, background: C.primarySoft, border: `1px solid ${C.primaryMuted}`, color: C.primary, fontSize: 16, cursor: "pointer", display: "flex", alignItems: "center", justifyContent: "center" }}>☰</button>
        ) : (
          <div style={{ display: "flex", gap: 4 }}>
            <button onClick={onNewSession} className="btn-new-session" style={{ flex: 1, display: "flex", alignItems: "center", gap: 6, padding: "7px 10px", background: C.primarySoft, border: `1px dashed ${C.primary}`, borderRadius: 10, color: C.primary, fontSize: 12, fontWeight: 500, cursor: "pointer", fontFamily: "inherit" }}>+ ახალი სესია</button>
            <button onClick={onToggle} style={{ width: 32, height: 32, borderRadius: 8, background: "transparent", border: `1px solid ${C.border}`, color: C.textMuted, fontSize: 11, cursor: "pointer", display: "flex", alignItems: "center", justifyContent: "center" }}>◀</button>
          </div>
        )}
      </div>
      <div style={{ flex: 1, overflow: "auto", padding: isCollapsed ? "4px 7px" : "4px 10px" }} className="chat-scroll">
        {isCollapsed ? sessions.map(s => {
          const active = s.id === activeId, si = STATUS_INDICATOR[s.status] || STATUS_INDICATOR.idle
          return <button key={s.id} onClick={() => onSelect(s.id)} title={s.title} style={{ width: 38, height: 38, borderRadius: 10, background: active ? C.primarySoft : "transparent", border: active ? `1px solid ${C.primaryMuted}` : "1px solid transparent", cursor: "pointer", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 15, marginBottom: 2, position: "relative" }}>
            {KIND_META[s.kind]?.icon || "💬"}
            <span style={{ position: "absolute", bottom: 2, right: 2, width: 7, height: 7, borderRadius: "50%", background: si.color, border: `2px solid ${C.surface}`, animation: si.pulse ? "pulse 2s infinite" : "none" }} />
            {s.unread && !active && <span style={{ position: "absolute", top: 1, right: 1, width: 8, height: 8, borderRadius: "50%", background: C.primary, border: `2px solid ${C.surface}` }} />}
          </button>
        }) : Array.from(groups.entries()).map(([kind, items]) => (
          <div key={kind} style={{ marginBottom: 8 }}>
            <div style={{ fontSize: 9.5, fontWeight: 600, textTransform: "uppercase", letterSpacing: 0.5, color: C.textMuted, padding: "6px 6px 3px", display: "flex", alignItems: "center", gap: 4 }}><span style={{ fontSize: 11 }}>{KIND_META[kind]?.icon}</span>{KIND_META[kind]?.label}</div>
            {items.map(s => { const active = s.id === activeId, si = STATUS_INDICATOR[s.status] || STATUS_INDICATOR.idle
              return <button key={s.id} onClick={() => onSelect(s.id)} style={{ display: "flex", alignItems: "center", gap: 8, width: "100%", padding: "7px 8px", background: active ? C.primarySoft : "transparent", border: active ? `1px solid ${C.primaryMuted}` : "1px solid transparent", borderRadius: 8, cursor: "pointer", textAlign: "left", fontFamily: "inherit", marginBottom: 1 }}>
                <span style={{ width: 7, height: 7, borderRadius: "50%", flexShrink: 0, background: si.color, animation: si.pulse ? "pulse 2s infinite" : "none" }} />
                <div style={{ flex: 1, minWidth: 0 }}><div style={{ fontSize: 11.5, fontWeight: active ? 600 : 500, color: active ? C.text : C.textSec, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{s.title}</div><div style={{ fontSize: 9.5, color: C.textMuted, marginTop: 1 }}>{s.updatedAt}</div></div>
                {s.unread && !active && <span style={{ width: 6, height: 6, borderRadius: "50%", background: C.primary, flexShrink: 0 }} />}
              </button>
            })}
          </div>
        ))}
      </div>
    </div>
  )
}

function WelcomeScreen({ hints, onHintClick, showSubtitle }) {
  return (
    <div style={{ flex: 1, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", padding: 40 }}>
      <div style={{ width: 72, height: 72, borderRadius: "50%", background: C.primarySoft, border: `2px solid ${C.primary}`, display: "flex", alignItems: "center", justifyContent: "center", fontSize: 28, fontWeight: 700, color: C.primary, marginBottom: 20, animation: "breathe 4s ease-in-out infinite" }}>K</div>
      <div style={{ fontSize: 20, fontWeight: 600, marginBottom: 6 }}>რაზე ვიმუშაოთ?</div>
      <div style={{ fontSize: 13, color: C.textMuted, maxWidth: 380, lineHeight: 1.6, textAlign: "center", marginBottom: 24 }}>მიამბე რა გინდა გააკეთო — flow-ს ავაწყობ, გავტესტავ, გავაანალიზებ.{showSubtitle && " ან აირჩიე მარცხნიდან არსებული სესია."}</div>
      <div style={{ display: "flex", flexWrap: "wrap", gap: 6, justifyContent: "center", maxWidth: 480 }}>
        {hints.map(h => <button key={h.label} onClick={() => onHintClick(h)} className="hint-chip" style={{ background: C.surface, border: `1px solid ${C.border}`, color: C.textSec, padding: "7px 16px", borderRadius: 20, fontSize: 11.5, cursor: "pointer", fontFamily: "inherit" }}>{h.label}</button>)}
      </div>
    </div>
  )
}

function ChatMessage({ msg, onOpenArtifact, compact }) {
  const isUser = msg.role === "user"
  return (
    <div style={{ display: "flex", gap: 8, marginBottom: 16, alignItems: "flex-start", flexDirection: isUser ? "row-reverse" : "row", animation: "fadeUp 0.3s ease" }}>
      <div style={{ width: 28, height: 28, borderRadius: "50%", flexShrink: 0, background: isUser ? C.accent : C.primary, color: C.textOnPrimary, display: "flex", alignItems: "center", justifyContent: "center", fontSize: isUser ? 9 : 11, fontWeight: 600 }}>{isUser ? "DG" : "K"}</div>
      <div style={{ maxWidth: compact ? "95%" : "82%", display: "flex", flexDirection: "column", gap: 6, minWidth: 0 }}>
        {msg.tools?.length > 0 && <div style={{ display: "flex", flexWrap: "wrap", gap: 4 }}>{msg.tools.map((t, i) => <span key={i} style={{ display: "inline-flex", alignItems: "center", gap: 5, padding: "3px 10px", borderRadius: 8, background: C.infoSoft, color: C.info, fontSize: 11, border: "1px solid rgba(112,168,224,0.15)" }}><span style={{ width: 5, height: 5, borderRadius: "50%", background: t.status === "done" ? C.success : C.warn, animation: t.status === "running" ? "pulse 1.2s infinite" : "none" }} />{t.label}{t.status === "done" && <span style={{ opacity: 0.7 }}>✓</span>}</span>)}</div>}
        {msg.content && <div style={{ padding: compact ? "9px 13px" : "11px 15px", borderRadius: 14, fontSize: compact ? 13 : 13.5, lineHeight: 1.6, whiteSpace: "pre-wrap", wordBreak: "break-word", ...(isUser ? { background: C.primarySoft, border: `1px solid ${C.primaryMuted}` } : { background: C.surface, border: `1px solid ${C.border}` }), color: C.text }}>{msg.content.split(/(\*\*[^*]+\*\*)/).map((part, i) => part.startsWith("**") && part.endsWith("**") ? <strong key={i} style={{ color: C.primary }}>{part.slice(2, -2)}</strong> : part)}</div>}
        {msg.artifact && <button onClick={onOpenArtifact} className="artifact-card" style={{ display: "flex", alignItems: "center", gap: 12, padding: "10px 14px", borderRadius: 12, width: "100%", background: C.surfaceRaised, border: `1px solid ${C.border}`, cursor: "pointer", textAlign: "left", fontFamily: "inherit", animation: "fadeUp 0.4s ease 0.15s both" }}>
          <span style={{ width: 38, height: 38, borderRadius: 10, background: C.primarySoft, border: `1px solid ${C.primaryMuted}`, display: "flex", alignItems: "center", justifyContent: "center", fontSize: 17, flexShrink: 0 }}>{msg.artifact.icon}</span>
          <div style={{ flex: 1, minWidth: 0 }}><div style={{ fontSize: 12.5, fontWeight: 600 }}>{msg.artifact.title}</div><div style={{ fontSize: 10.5, color: C.textMuted, marginTop: 1 }}>{msg.artifact.subtitle}</div></div>
          <span style={{ fontSize: 10, fontWeight: 600, color: C.primary, padding: "5px 10px", borderRadius: 8, background: C.primarySoft, border: `1px solid ${C.primaryMuted}`, whiteSpace: "nowrap", flexShrink: 0 }}>⤢ გახსნა</span>
        </button>}
        {msg.quickActions && <div style={{ display: "flex", flexWrap: "wrap", gap: 5, animation: "fadeUp 0.3s ease 0.25s both" }}>{msg.quickActions.map((qa, i) => <button key={i} className="hint-chip" style={{ padding: "5px 12px", borderRadius: 16, background: C.surface, border: `1px solid ${C.border}`, color: C.textSec, fontSize: 11, cursor: "pointer", fontFamily: "inherit" }}>{qa.label}</button>)}</div>}
      </div>
    </div>
  )
}

function TypingIndicator() {
  return <div style={{ display: "flex", gap: 8, marginBottom: 12, animation: "fadeUp 0.3s ease" }}><div style={{ width: 28, height: 28, borderRadius: "50%", background: C.primary, color: C.textOnPrimary, display: "flex", alignItems: "center", justifyContent: "center", fontSize: 11, fontWeight: 600 }}>K</div><div style={{ padding: "10px 14px", borderRadius: 14, background: C.surface, border: `1px solid ${C.border}` }}><div style={{ display: "flex", gap: 4 }}>{[0, 0.2, 0.4].map((d, i) => <span key={i} style={{ width: 5, height: 5, borderRadius: "50%", background: C.primary, animation: `pulse 1.2s infinite ${d}s` }} />)}</div></div></div>
}

const ChatInput = ({ value, onChange, onSend, placeholder }) => {
  const ref = useRef(null)
  useEffect(() => { if (ref.current) { ref.current.style.height = "auto"; ref.current.style.height = `${Math.min(ref.current.scrollHeight, 80)}px` } }, [value])
  return <div style={{ padding: "8px 16px 12px", flexShrink: 0 }}><div style={{ display: "flex", alignItems: "flex-end", gap: 6, background: C.surface, border: `1.5px solid ${C.border}`, borderRadius: 14, padding: "8px 12px" }}>
    <textarea ref={ref} value={value} onChange={e => onChange(e.target.value)} onKeyDown={e => { if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); onSend() } }} placeholder={placeholder} rows={1} style={{ flex: 1, background: "none", border: "none", color: C.text, fontSize: 13.5, fontFamily: "inherit", resize: "none", outline: "none", maxHeight: 80, lineHeight: 1.5 }} />
    <button onClick={onSend} disabled={!value.trim()} style={{ background: value.trim() ? C.primary : C.surfaceDim, border: "none", color: value.trim() ? C.textOnPrimary : C.textMuted, width: 30, height: 30, borderRadius: "50%", cursor: value.trim() ? "pointer" : "default", display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0 }}>
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.5} strokeLinecap="round" strokeLinejoin="round" style={{ width: 13, height: 13 }}><line x1="22" y1="2" x2="11" y2="13" /><polygon points="22 2 15 22 11 13 2 9 22 2" /></svg>
    </button>
  </div></div>
}

function PanelBtn({ children, onClick, small }) {
  return <button onClick={onClick} className="ctx-btn" style={{ width: small ? 24 : 28, height: small ? 24 : 28, borderRadius: 6, background: C.surfaceDim, border: `1px solid ${C.border}`, color: C.textMuted, cursor: "pointer", display: "flex", alignItems: "center", justifyContent: "center", fontSize: small ? 12 : 14 }}>{children}</button>
}

function Styles() {
  return <style>{`
    * { box-sizing: border-box; margin: 0; padding: 0; }
    @keyframes fadeUp { from { opacity: 0; transform: translateY(6px); } to { opacity: 1; transform: translateY(0); } }
    @keyframes breathe { 0%, 100% { transform: scale(1); opacity: 0.85; } 50% { transform: scale(1.06); opacity: 1; } }
    @keyframes slideIn { from { opacity: 0; transform: translateX(30px); } to { opacity: 1; transform: translateX(0); } }
    @keyframes pulse { 0%, 100% { opacity: 0.35; } 50% { opacity: 1; } }
    .chat-scroll::-webkit-scrollbar { width: 4px; }
    .chat-scroll::-webkit-scrollbar-thumb { background: ${C.border}; border-radius: 4px; }
    .chat-scroll::-webkit-scrollbar-track { background: transparent; }
    .hint-chip:hover { border-color: ${C.primary} !important; color: ${C.primary} !important; background: ${C.primarySoft} !important; }
    .artifact-card:hover { border-color: ${C.primary} !important; background: ${C.primarySoft} !important; }
    .flow-node:hover { background: ${C.surfaceRaised} !important; transform: translateY(-1px); box-shadow: 0 4px 12px rgba(0,0,0,0.15); }
    .ctx-btn:hover { border-color: ${C.primary} !important; color: ${C.text} !important; }
    .btn-new-session:hover { background: ${C.primary} !important; color: ${C.textOnPrimary} !important; border-style: solid !important; }
  `}</style>
}
