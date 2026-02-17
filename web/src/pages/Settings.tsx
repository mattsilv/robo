import { useAuth } from '../contexts/AuthContext'

export function SettingsPage() {
  const { user } = useAuth()

  return (
    <div>
      <h1 className="text-2xl font-bold mb-6">Settings</h1>

      <div className="bg-[var(--surface)] rounded-xl p-5 border border-[var(--surface-raised)]">
        <h2 className="font-semibold mb-4">Account</h2>
        <div className="space-y-3 text-sm">
          <div className="flex justify-between">
            <span className="text-[var(--text-dim)]">Name</span>
            <span>{user?.first_name || '—'}</span>
          </div>
          <div className="flex justify-between">
            <span className="text-[var(--text-dim)]">Email</span>
            <span>{user?.email || '—'}</span>
          </div>
        </div>
      </div>

      <p className="text-xs text-[var(--text-muted)] mt-4">
        Settings sync and device management coming in Phase 4.
      </p>
    </div>
  )
}
