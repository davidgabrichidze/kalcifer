import ChatPanel from '../components/ChatPanel'

export default function WorkPage() {
  return (
    <div className="flex flex-1 justify-center overflow-hidden">
      <div
        className="flex flex-col"
        style={{ width: '100%', maxWidth: 640, minHeight: 0 }}
      >
        <ChatPanel />
      </div>
    </div>
  )
}
