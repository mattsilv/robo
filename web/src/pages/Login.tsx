import { useAuth } from '../contexts/AuthContext'
import { Navigate } from 'react-router-dom'

export function LoginPage() {
  const { user, loading } = useAuth()

  if (loading) return null
  if (user) return <Navigate to="/" replace />

  return (
    <div className="min-h-screen flex items-center justify-center">
      <div className="bg-[var(--surface)] rounded-2xl p-8 max-w-sm w-full text-center">
        <div className="text-3xl font-bold text-[var(--blue)] mb-2">ROBO</div>
        <p className="text-[var(--text-dim)] text-sm mb-8">The Context Cultivator</p>

        <button
          className="w-full bg-white text-black rounded-lg py-3 px-4 font-medium text-sm flex items-center justify-center gap-2 hover:bg-gray-100 transition-colors"
          onClick={() => {
            // Apple Sign In will be wired after Apple Developer Portal setup
            alert('Sign in with Apple — configure Apple Services ID first')
          }}
        >
          <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor">
            <path d="M11.182 0a3.31 3.31 0 0 0-2.198 1.121A3.253 3.253 0 0 0 8 3.3a2.79 2.79 0 0 0 2.218-1.1A3.14 3.14 0 0 0 11.182 0zM12.5 4.2c-1.4 0-2 .8-2.9.8S8.4 4.2 7.2 4.2C5.4 4.2 3.5 5.7 3.5 8.8c0 2 .8 4.1 1.7 5.4.8 1.1 1.5 2 2.5 2 .9 0 1.4-.6 2.6-.6s1.6.6 2.6.6 1.6-.8 2.4-1.8c.5-.7.7-1 1-1.8-2.5-1-2.9-4.6-.5-6 -.7-.9-1.7-1.5-2.8-1.5-.1-.1-.3-.1-.5-.1z" />
          </svg>
          Sign in with Apple
        </button>

        <p className="text-[var(--text-muted)] text-xs mt-6">
          Same account as the iOS app
        </p>
      </div>
    </div>
  )
}
