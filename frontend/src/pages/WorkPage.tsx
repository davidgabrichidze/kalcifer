import ChatPanel from '../components/ChatPanel'

export default function WorkPage() {
  return (
    <div className="flex flex-1 overflow-hidden">
      {/* Chat area — takes full width for now, will share with context panel later */}
      <div className="flex flex-1 flex-col" style={{ minWidth: 0 }}>
        <ChatPanel />
      </div>
    </div>
  )
}
