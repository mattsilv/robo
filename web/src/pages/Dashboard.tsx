import { useAuth } from '../contexts/AuthContext'

export function DashboardPage() {
  const { user } = useAuth()

  return (
    <div>
      <h1 className="text-2xl font-bold mb-6">
        Welcome{user?.first_name ? `, ${user.first_name}` : ''}
      </h1>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <DashCard title="HITs" description="Create and manage Human Intelligence Tasks" href="/hits" />
        <DashCard title="Chat" description="Talk to your AI agents" href="/chat" />
        <DashCard title="Settings" description="Manage your account and devices" href="/settings" />
      </div>
    </div>
  )
}

function DashCard({ title, description, href }: { title: string; description: string; href: string }) {
  return (
    <a
      href={href}
      className="block bg-[var(--surface)] rounded-xl p-5 border border-[var(--surface-raised)] hover:border-[var(--blue)] transition-colors"
    >
      <h2 className="font-semibold mb-1">{title}</h2>
      <p className="text-sm text-[var(--text-dim)]">{description}</p>
    </a>
  )
}
