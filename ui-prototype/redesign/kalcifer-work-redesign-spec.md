# Kalcifer Work Page — Redesign Spec & Implementation Plan

## 1. რა იცვლება და რატომ

### პრობლემა

არსებული WorkPage-ის layout სისტემა 5 stage-ს იყენებს (`welcome → lobby → chat → split → context`), სადაც `split` და `context` თითქმის იდენტურია — განსხვავება მხოლოდ CSS flex პროპორციებშია. Right panel-ს ორი როლი აქვს (ArtifactPanel ჩათის შიგნით + context area ცალკე), რაც ატომიზირებულ ლეიაუთს ქმნის. Resize handle არსებობს CSS-ში, მაგრამ ფუნქციონალურად არ მუშაობს.

### გადაწყვეტა

Cowork-ის პატერნის მიხედვით: მარჯვენა მხარე = ერთი კონტექსტური კონტეინერი ორი რეჟიმით (sidebar / editor). Stage სისტემა მარტივდება 4 stage-მდე. Drag-to-resize ფუნქციონალური ხდება.

### პროტოტიპი

`kalcifer-work-prototype.html` — ბრაუზერში გასაშვები interactive prototype. ყველა ქვემოთ აღწერილი ცვლილება იქ ვიზუალურად გატესტილია.

---

## 2. Stage სისტემა (ახალი)

| Stage | მარცხენა sidebar | ჩათი | მარჯვენა panel | rightMode |
|-------|-----------------|------|----------------|-----------|
| `welcome` | hidden | centered welcome | hidden | `"hidden"` |
| `lobby` | expanded (210px) | centered welcome | hidden | `"hidden"` |
| `chat` | expanded (210px) | full-width | sidebar (300px, fixed) | `"sidebar"` |
| `split` | collapsed (52px) | flex ratio | editor (flex ratio) | `"editor"` |

**წაშლილი stage:** `context` — აღარ არსებობს. `split` stage-ში პროპორციები drag-ით რეგულირდება (splitRatio: 0.2–0.8).

### Stage transitions

```
welcome ──[send/hint click]──→ chat (+ rightMode: sidebar)
lobby   ──[send/hint click]──→ chat (+ rightMode: sidebar)
chat    ──[artifact open]────→ split (+ rightMode: editor, sidebar collapses)
split   ──[← back button]───→ chat (+ rightMode: sidebar, sidebar expands)
split   ──[✕ close]─────────→ chat (+ rightMode: hidden → sidebar)
any     ──[Kalcifer logo]───→ welcome (reset)
```

---

## 3. მარჯვენა panel — ორი რეჟიმი

### 3.1 Sidebar Mode (`rightMode: "sidebar"`)

ჩატის გვერდით, 300px ფიქსირებული სიგანე. შეიცავს collapsible სექციებს:

**Progress / Todo** — ზემოდან
- აგენტის მიმდინარე სამუშაოს ტრეკერი
- ფორმატი: `● label (detail)` თითოეული ნაბიჯისთვის
- Header: `"მიმდინარეობს..."` (running) ან `"N/M შესრულდა"` (done)
- მწვანე/ყვითელი წერტილი status-ის მიხედვით
- Default: expanded running-ის დროს, collapsed სრულყოფისას

**Artifacts** — შუაში
- ჩათის დროს დაგროვილი არტეფაქტები (flows, analyses, etc.)
- Card ფორმატი: icon + title + subtitle + → arrow
- Click → rightMode: "editor" (ხსნის split view-ს)
- Default: expanded

**Context / Skills** — ქვემოთ
- აქტიური skills/tools + session metadata
- Badge ფორმატი: SKILL/META tag + label + detail
- Default: collapsed

### 3.2 Editor Mode (`rightMode: "editor"`)

Artifact-ის სრული preview/editor. ჩანაცვლებს sidebar-ს.

Header:
- `← back` button (sidebar-ზე დაბრუნება)
- Artifact title + status badge + version
- `✕` close button

Content:
- Flow canvas (FlowEditorInline) ან სხვა artifact ტიპის viewer
- Tab bar: `✎ Edit | ▶ Simulate | ◉ Live`

Footer:
- Stats bar: `N nodes · M edges · Ready`

---

## 4. Drag-to-Resize

Split stage-ში ჩათსა და editor-ს შორის drag handle.

**Implementation:**
- State: `splitRatio` (0.2 – 0.8, default 0.45)
- Handle: 6px wide, cursor: col-resize
- Visual: 2px vertical line, ნარინჯისფერი hover/drag-ზე
- Events: mousedown → document mousemove → mouseup
- Body: `cursor: col-resize` + `user-select: none` drag-ის დროს

**CSS flex calculation:**
- Chat: `flex: ${splitRatio}`
- Editor: `flex: ${1 - splitRatio}`
- minWidth: 280px (chat), 240px (editor)

---

## 5. Tool Badges — "სამზარეულოს ფანჯარა"

აგენტის tool activity-ს ჩვენება ჩატის შეტყობინებებში.

### პოზიცია: ტექსტის ქვემოთ

ტექსტი (კერძი) → tool badges (სამზარეულო) → artifact card → quick actions

### ვარიანტი: Minimal (expandable)

**დაკეცილი (default):**
```
● 2 სამუშაო შესრულდა ▼
```
ერთი ხაზი, clickable. მწვანე წერტილი (done) ან ყვითელი (running).

**გაშლილი (click):**
```
● 2 სამუშაო შესრულდა ▲
  ● ფლოუს შექმნა ✓
  ● 5 ნაბიჯის დამატება ✓
```

Running-ის დროს:
```
● ფლოუს შექმნა... ▼
```

---

## 6. Quick Actions — მხოლოდ ბოლო AI შეტყობინებაზე

**პრობლემა:** ძველ შეტყობინებებზე quick actions ("გავააქტიურო?", "Dry Run") მოძველებულია.

**გადაწყვეტა:** `isLastAI` prop — quick actions რენდერდება მხოლოდ ბოლო AI შეტყობინებაზე. ისტორიაში scrolling-ისას ძველი actions აღარ ჩანს.

```typescript
const lastAIIndex = messages.findLastIndex(m => m.role === 'ai')
// ChatMessage-ში:
{isLastAI && msg.quickActions && <QuickActions actions={msg.quickActions} />}
```

---

## 7. Input Field — გაძლიერებული

**ვიზუალი:**
- padding: 10px 14px
- borderRadius: 16px
- Focus: ნარინჯისფერი border + glow shadow (`0 0 0 3px rgba(primary, 0.12)`)
- 📎 attach button მარცხნივ
- Send button: 34px, rounded, ნარინჯისფერი filled-ის დროს
- Keyboard hints ქვემოთ: `Enter გასაგზავნად · Shift+Enter ახალი ხაზი`

---

## 8. CSS Architecture

### ახალი custom properties (index.css-ში დასამატებელი)

```css
/* Split resize */
--split-ratio: 0.45;
--split-min-chat: 280px;
--split-min-editor: 240px;

/* Right panel */
--right-sidebar-width: 300px;
--right-transition: 0.35s cubic-bezier(0.4, 0, 0.2, 1);

/* Input */
--input-glow: 0 0 0 3px rgba(var(--color-primary-rgb), 0.12);
```

### work-stages.css — განახლებული

წაშლილი: `[data-stage="context"]` ყველა rule.
შეცვლილი: `[data-stage="split"]` — flex ratio CSS variable-დან.

---

## 9. ახალი/შეცვლილი ფაილები

| ფაილი | ტიპი | აღწერა |
|-------|------|--------|
| `src/pages/WorkPage.tsx` | შეცვლა | Stage system: 4 stage, splitRatio state, rightMode state, drag handler |
| `src/pages/work-stages.css` | შეცვლა | context stage წაშლა, split flex ratio |
| `src/components/RightPanel.tsx` | **ახალი** | Container: sidebar mode ↔ editor mode |
| `src/components/RightSidebar.tsx` | **ახალი** | Progress + Artifacts + Context (collapsible sections) |
| `src/components/CollapsibleSection.tsx` | **ახალი** | Reusable collapsible with header/icon/children |
| `src/components/DragHandle.tsx` | **ახალი** | Vertical drag-to-resize handle |
| `src/components/ToolBadges.tsx` | **ახალი** | Minimal expandable tool activity display |
| `src/components/ChatPanel.tsx` | შეცვლა | Badge position, quick actions only on last AI msg |
| `src/components/ChatInput.tsx` | **ახალი** | Extract + enhance: glow, attach btn, hints |
| `src/components/ArtifactPanel.tsx` | წაშლა | ფუნქციონალი RightSidebar-ში გადავიდა |
| `src/components/artifact-panel.css` | წაშლა | |
| `src/components/right-panel.css` | **ახალი** | Right panel styles |
| `src/components/chat-input.css` | **ახალი** | Enhanced input styles |

---

## 10. Implementation Plan — Claude Code-ისთვის

### წინაპირობა

```bash
cd kalcifer/frontend
npm install  # dependencies up to date
npm run test  # baseline — ყველა ტესტი გადის
```

---

### ფაზა 1: საფუძველი — CollapsibleSection + DragHandle (ორი atomic კომპონენტი)

**ნაბიჯი 1.1:** `src/components/CollapsibleSection.tsx`
```typescript
interface CollapsibleSectionProps {
  title: string
  icon?: React.ReactNode
  expanded: boolean
  onToggle: () => void
  children: React.ReactNode
}
```
- CSS: border-bottom, rotate chevron animation
- ტესტი: expand/collapse toggle, children visibility

**ნაბიჯი 1.2:** `src/components/DragHandle.tsx`
```typescript
interface DragHandleProps {
  onDrag: (clientX: number) => void
}
```
- mousedown → document mousemove/mouseup
- body cursor + user-select during drag
- Visual: 6px wide, 2px line, primary color on hover/drag
- ტესტი: renders, drag event fires onDrag

**ვალიდაცია:** `npm run test && npm run build` — no errors

---

### ფაზა 2: ToolBadges + ChatInput — ჩატის კომპონენტები

**ნაბიჯი 2.1:** `src/components/ToolBadges.tsx`
```typescript
interface ToolBadgesProps {
  tools: ToolActivity[]
}
```
- Default: collapsed single-line summary
- Click: expand to show all tools
- Internal state: `expanded` (boolean)
- Summary logic: running → "ფლოუს შექმნა...", done → "2 სამუშაო შესრულდა"

**ნაბიჯი 2.2:** `src/components/ChatInput.tsx`
- Extract from ChatPanel: input + textarea + send button
- Add: 📎 attach button (placeholder), focus glow CSS, keyboard hints
- Props: `value`, `onChange`, `onSend`, `placeholder`

**ნაბიჯი 2.3:** ChatPanel.tsx — integration
- Import ToolBadges, render BELOW message text
- Import ChatInput, replace inline input code
- Quick actions: compute `lastAIIndex`, pass `isLastAI` prop
- TOOL_LABELS dict → ToolBadges-ში გადატანა (or shared constants)

**ვალიდაცია:** `npm run test` — ChatPanel tests pass, manual visual check

---

### ფაზა 3: RightPanel — sidebar + editor modes

**ნაბიჯი 3.1:** `src/components/RightSidebar.tsx`
- CollapsibleSection × 3: Progress, Artifacts, Context
- Progress: receives `toolActivities` from ChatPanel (or WorkPage)
- Artifacts: migrated from ArtifactPanel (same Artifact type, same cards)
- Context: skills/meta items (from session classification)
- Props interface matching WorkPage state

**ნაბიჯი 3.2:** `src/components/RightPanel.tsx`
```typescript
interface RightPanelProps {
  mode: 'sidebar' | 'editor'
  // sidebar props
  progressSteps: ToolActivity[]
  artifacts: Artifact[]
  contextItems: ContextItem[]
  onArtifactClick: (artifact: Artifact) => void
  // editor props
  editorContent: ContextContent
  onBack: () => void
  onClose: () => void
  onOpenFullEditor?: (flowId: string) => void
}
```
- Conditional render: sidebar ↔ editor based on mode
- Editor: wraps FlowEditorInline or FlowCanvas (existing components)
- Slide-in animation

**ნაბიჯი 3.3:** Delete `ArtifactPanel.tsx` + `artifact-panel.css`
- ფუნქციონალი RightSidebar-ში გადავიდა
- Artifact type export გადავიდეს types/ ან lib/types.ts-ში

**ვალიდაცია:** `npm run build` — no import errors

---

### ფაზა 4: WorkPage — stage system overhaul

**ნაბიჯი 4.1:** Stage type update
```typescript
type Stage = 'welcome' | 'lobby' | 'chat' | 'split'
// წაშლილი: 'context'
```

**ნაბიჯი 4.2:** ახალი state variables
```typescript
const [rightMode, setRightMode] = useState<'hidden' | 'sidebar' | 'editor'>('hidden')
const [splitRatio, setSplitRatio] = useState(0.45)
```

**ნაბიჯი 4.3:** Stage ↔ rightMode sync
- `welcome/lobby` → rightMode: hidden
- `chat` → rightMode: sidebar (auto-transition)
- `split` → rightMode: editor

**ნაბიჯი 4.4:** Drag handler
```typescript
const mainRef = useRef<HTMLDivElement>(null)
const handleDrag = useCallback((clientX: number) => {
  const rect = mainRef.current?.getBoundingClientRect()
  if (!rect) return
  const sidebarW = stage === 'split' ? 52 : 210
  const ratio = (clientX - rect.left - sidebarW) / (rect.width - sidebarW)
  setSplitRatio(Math.max(0.2, Math.min(0.8, ratio)))
}, [stage])
```

**ნაბიჯი 4.5:** JSX restructure
- წაშლა: inline ArtifactPanel render
- წაშლა: handleToggleExpand (split↔context)
- დამატება: `<DragHandle onDrag={handleDrag} />` split-ში
- დამატება: `<RightPanel mode={rightMode} ... />` (conditional)
- Chat div: `flex: ${isEditorMode ? splitRatio : 1}`

**ნაბიჯი 4.6:** Callbacks update
- `openEditor` → setRightMode('editor'), setStage('split')
- `backToSidebar` → setRightMode('sidebar'), setStage('chat')
- `closeRightPanel` → setRightMode('hidden'), setStage('chat')
- წაშლა: `handleToggleExpand`

**ვალიდაცია:** `npm run build && npm run test`

---

### ფაზა 5: CSS — work-stages.css overhaul

**ნაბიჯი 5.1:** წაშლა `[data-stage="context"]` rules (3 blocks)

**ნაბიჯი 5.2:** `[data-stage="split"]` update
```css
[data-stage="split"] .work-chat {
  flex: var(--split-ratio, 0.45);
  min-width: var(--split-min-chat, 280px);
  border-right: none; /* DragHandle ანაცვლებს */
}

[data-stage="split"] .work-context-area {
  flex: calc(1 - var(--split-ratio, 0.45));
  min-width: var(--split-min-editor, 240px);
  opacity: 1;
}
```

**ნაბიჯი 5.3:** Right panel CSS
- `right-panel.css`: slide-in animation, sidebar/editor transitions
- `chat-input.css`: focus glow, attach button, keyboard hints

**ნაბიჯი 5.4:** index.css — custom properties
- დამატება: split/input variables ყველა theme-ში

**ვალიდაცია:** `npm run build` — no CSS errors

---

### ფაზა 6: Sidebar behavior update

**ნაბიჯი 6.1:** Sidebar.tsx — collapsed mode
- `split` stage-ში auto-collapse to 52px (icon-only)
- `chat` stage-ში expand back to 210px
- Cmd+\ shortcut (already exists? — verify and add if missing)

**ვალიდაცია:** manual test — sidebar collapses in split, expands in chat

---

### ფაზა 7: ტესტები

**ნაბიჯი 7.1:** ახალი ტესტები
- `CollapsibleSection.test.tsx` — toggle, children render
- `DragHandle.test.tsx` — drag events
- `ToolBadges.test.tsx` — collapsed/expanded, running/done states
- `RightPanel.test.tsx` — sidebar/editor mode switch

**ნაბიჯი 7.2:** არსებული ტესტების update
- `ChatPanel.test.tsx` — ToolBadges integration, ChatInput extraction
- `WorkPage.test.tsx` (if exists) — stage transitions without 'context'

**ვალიდაცია:** `npm run test -- --trace` — all pass

---

### ფაზა 8: Final validation

```bash
npm run test           # ყველა ტესტი
npm run build          # production build
npx tsc --noEmit       # type check
npm run lint           # ESLint
```

Visual checklist:
- [ ] Welcome → hint click → chat + sidebar appears
- [ ] Sidebar: Progress updates during AI response
- [ ] Artifact card click → split + editor opens
- [ ] Drag handle: resize chat/editor ratio
- [ ] ← back → returns to sidebar mode
- [ ] ✕ close → hides right panel
- [ ] Tool badges: text first, badges below, expandable
- [ ] Quick actions: only on last AI message
- [ ] Input: glow on focus, attach button, hints
- [ ] Cmd+\ toggles left sidebar
- [ ] All themes work (8 themes × 2 modes)

---

## 11. არ შეიცვლება

- TopBar.tsx — უცვლელი
- FlowCanvas.tsx — უცვლელი (RightPanel wraps it)
- FlowEditorInline.tsx — უცვლელი (RightPanel wraps it)
- lib/api.ts — უცვლელი
- lib/chat.ts — უცვლელი
- lib/themes.ts — უცვლელი
- pages/EnginePage.tsx — უცვლელი
- pages/BrowsePage.tsx — უცვლელი
- pages/editor/* — უცვლელი

---

## 12. რისკები და ღია კითხვები

**რისკი: Progress data source.** პროტოტიპში progress steps demo data-ა. რეალურ სისტემაში ChatPanel-ის tool activities → RightSidebar-ის progress. ეს lifting state up მოითხოვს (ChatPanel → WorkPage → RightPanel).

**რისკი: ArtifactPanel migration.** ArtifactPanel-ის წაშლა და RightSidebar-ში ინტეგრაცია — Artifact type-ის re-export საჭიროა.

**ღია კითხვა: Attach button.** პროტოტიპში placeholder-ია. რეალური file upload ცალკე task.

**ღია კითხვა: Quick actions persistence.** ბოლო AI შეტყობინებაზე ჩვენება მარტივი გადაწყვეტაა. სამომავლოდ: server-side action validity check.

**ღია კითხვა: Sidebar collapse animation.** 210px → 52px transition — არსებული Sidebar.tsx-ს უნდა ჰქონდეს collapsed mode. თუ არ აქვს, ფაზა 6-ში იმპლემენტაცია.
