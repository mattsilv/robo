import { Outlet, NavLink } from 'react-router-dom'
import { useAuth } from '../contexts/AuthContext'

const navItems = [
  { to: '/', label: 'Dashboard' },
  { to: '/hits', label: 'HITs' },
  { to: '/chat', label: 'Chat' },
  { to: '/settings', label: 'Settings' },
]

export function Layout() {
  const { user, logout } = useAuth()

  return (
    <div className="min-h-screen flex flex-col">
      <nav className="border-b border-[var(--surface-raised)] px-6 py-3 flex items-center justify-between">
        <div className="flex items-center gap-6">
          <span className="text-lg font-bold text-[var(--blue)]">ROBO</span>
          <div className="flex gap-4">
            {navItems.map(({ to, label }) => (
              <NavLink
                key={to}
                to={to}
                className={({ isActive }) =>
                  `text-sm transition-colors ${isActive ? 'text-[var(--text)]' : 'text-[var(--text-dim)] hover:text-[var(--text)]'}`
                }
              >
                {label}
              </NavLink>
            ))}
          </div>
        </div>
        {user && (
          <div className="flex items-center gap-4">
            <span className="text-sm text-[var(--text-dim)]">{user.first_name || user.email}</span>
            <button
              onClick={logout}
              className="text-sm text-[var(--text-muted)] hover:text-[var(--text-dim)] transition-colors"
            >
              Sign out
            </button>
          </div>
        )}
      </nav>
      <main className="flex-1 p-6 max-w-5xl mx-auto w-full">
        <Outlet />
      </main>
    </div>
  )
}
