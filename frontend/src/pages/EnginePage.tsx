export default function EnginePage() {
  return (
    <div className="flex flex-1 items-center justify-center">
      <div className="text-center">
        <h2
          className="mb-2 text-xl font-semibold"
          style={{ color: 'var(--color-text)' }}
        >
          Engine Room
        </h2>
        <p
          className="text-sm"
          style={{ color: 'var(--color-text-muted)' }}
        >
          Live monitoring — coming soon
        </p>
      </div>
    </div>
  )
}
