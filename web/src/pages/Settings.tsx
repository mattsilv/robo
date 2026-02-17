import { useState, useEffect } from 'react'
import { useAuth } from '../contexts/AuthContext'
import { api } from '../lib/api'

type McpToken = {
  device_id: string
  token: string
  label: string
  last_seen_at: string | null
}

type SettingsData = {
  first_name: string | null
  mcp_tokens: McpToken[]
}

export function SettingsPage() {
  const { user, refresh } = useAuth()
  const [settings, setSettings] = useState<SettingsData | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  // Name editing
  const [editingName, setEditingName] = useState(false)
  const [nameValue, setNameValue] = useState('')
  const [saving, setSaving] = useState(false)
  const [saveSuccess, setSaveSuccess] = useState(false)

  // Token visibility
  const [revealedTokens, setRevealedTokens] = useState<Set<string>>(new Set())
  const [copiedToken, setCopiedToken] = useState<string | null>(null)

  useEffect(() => {
    fetchSettings()
  }, [])

  async function fetchSettings() {
    try {
      const data = await api<SettingsData>('/api/settings')
      setSettings(data)
      setNameValue(data.first_name ?? '')
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load settings')
    } finally {
      setLoading(false)
    }
  }

  async function saveName() {
    if (!nameValue.trim()) return
    setSaving(true)
    setSaveSuccess(false)
    try {
      await api('/api/settings', {
        method: 'PATCH',
        body: JSON.stringify({ first_name: nameValue.trim() }),
      })
      setSettings((s) => s ? { ...s, first_name: nameValue.trim() } : s)
      setEditingName(false)
      setSaveSuccess(true)
      refresh()
      setTimeout(() => setSaveSuccess(false), 2000)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to save')
    } finally {
      setSaving(false)
    }
  }

  function toggleToken(deviceId: string) {
    setRevealedTokens((prev) => {
      const next = new Set(prev)
      if (next.has(deviceId)) next.delete(deviceId)
      else next.add(deviceId)
      return next
    })
  }

  async function copyToken(token: string, deviceId: string) {
    await navigator.clipboard.writeText(token)
    setCopiedToken(deviceId)
    setTimeout(() => setCopiedToken(null), 2000)
  }

  function maskToken(token: string) {
    if (token.length <= 8) return '••••••••'
    return token.slice(0, 4) + '••••••••' + token.slice(-4)
  }

  function formatDate(iso: string | null) {
    if (!iso) return 'Never'
    return new Date(iso + 'Z').toLocaleDateString(undefined, {
      month: 'short', day: 'numeric', year: 'numeric',
      hour: '2-digit', minute: '2-digit',
    })
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <div className="animate-spin w-6 h-6 border-2 border-[var(--blue)] border-t-transparent rounded-full" />
      </div>
    )
  }

  if (error && !settings) {
    return (
      <div className="bg-red-500/10 border border-red-500/30 rounded-xl p-4 text-red-400">
        {error}
      </div>
    )
  }

  return (
    <div className="max-w-2xl">
      <h1 className="text-2xl font-bold mb-6">Settings</h1>

      {error && (
        <div className="bg-red-500/10 border border-red-500/30 rounded-xl p-3 text-red-400 text-sm mb-4">
          {error}
          <button onClick={() => setError(null)} className="ml-2 underline">Dismiss</button>
        </div>
      )}

      {saveSuccess && (
        <div className="bg-green-500/10 border border-green-500/30 rounded-xl p-3 text-green-400 text-sm mb-4">
          Settings saved successfully.
        </div>
      )}

      {/* Account Section */}
      <section className="bg-[var(--surface)] rounded-xl p-5 border border-[var(--surface-raised)] mb-4">
        <h2 className="font-semibold mb-4">Account</h2>
        <div className="space-y-3 text-sm">
          <div className="flex items-center justify-between">
            <span className="text-[var(--text-dim)]">Name</span>
            {editingName ? (
              <div className="flex items-center gap-2">
                <input
                  type="text"
                  value={nameValue}
                  onChange={(e) => setNameValue(e.target.value)}
                  maxLength={50}
                  className="bg-[var(--bg)] border border-[var(--surface-raised)] rounded-lg px-3 py-1.5 text-sm w-48 focus:outline-none focus:border-[var(--blue)]"
                  autoFocus
                  onKeyDown={(e) => {
                    if (e.key === 'Enter') saveName()
                    if (e.key === 'Escape') { setEditingName(false); setNameValue(settings?.first_name ?? '') }
                  }}
                />
                <button
                  onClick={saveName}
                  disabled={saving || !nameValue.trim()}
                  className="px-3 py-1.5 bg-[var(--blue)] text-white rounded-lg text-sm font-medium disabled:opacity-50"
                >
                  {saving ? 'Saving...' : 'Save'}
                </button>
                <button
                  onClick={() => { setEditingName(false); setNameValue(settings?.first_name ?? '') }}
                  className="px-3 py-1.5 text-[var(--text-dim)] hover:text-[var(--text)] text-sm"
                >
                  Cancel
                </button>
              </div>
            ) : (
              <div className="flex items-center gap-2">
                <span>{settings?.first_name || '—'}</span>
                <button
                  onClick={() => setEditingName(true)}
                  className="text-[var(--blue)] hover:underline text-xs"
                >
                  Edit
                </button>
              </div>
            )}
          </div>
          <div className="flex justify-between">
            <span className="text-[var(--text-dim)]">Email</span>
            <span>{user?.email || '—'}</span>
          </div>
        </div>
      </section>

      {/* Linked Devices Section */}
      <section className="bg-[var(--surface)] rounded-xl p-5 border border-[var(--surface-raised)]">
        <h2 className="font-semibold mb-4">Linked Devices</h2>
        {(!settings?.mcp_tokens || settings.mcp_tokens.length === 0) ? (
          <p className="text-sm text-[var(--text-dim)]">
            No devices linked to your account. Open the Robo app and sign in to link a device.
          </p>
        ) : (
          <div className="space-y-3">
            {settings.mcp_tokens.map((device) => (
              <div
                key={device.device_id}
                className="bg-[var(--bg)] rounded-lg p-4 border border-[var(--surface-raised)]"
              >
                <div className="flex items-center justify-between mb-2">
                  <span className="font-medium text-sm">{device.label}</span>
                  <span className="text-xs text-[var(--text-muted)]">
                    Last seen: {formatDate(device.last_seen_at)}
                  </span>
                </div>
                <div className="flex items-center gap-2">
                  <code className="text-xs bg-[var(--surface)] px-2 py-1 rounded flex-1 font-mono overflow-hidden text-ellipsis">
                    {revealedTokens.has(device.device_id)
                      ? device.token
                      : maskToken(device.token)}
                  </code>
                  <button
                    onClick={() => toggleToken(device.device_id)}
                    className="text-xs text-[var(--text-dim)] hover:text-[var(--text)] px-2 py-1"
                  >
                    {revealedTokens.has(device.device_id) ? 'Hide' : 'Reveal'}
                  </button>
                  <button
                    onClick={() => copyToken(device.token, device.device_id)}
                    className="text-xs text-[var(--blue)] hover:underline px-2 py-1"
                  >
                    {copiedToken === device.device_id ? 'Copied!' : 'Copy'}
                  </button>
                </div>
              </div>
            ))}
          </div>
        )}
      </section>
    </div>
  )
}
