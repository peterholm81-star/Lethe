import { createClient } from '@supabase/supabase-js'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL as string | undefined
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined

export const supabase =
  supabaseUrl && supabaseAnonKey
    ? createClient(supabaseUrl, supabaseAnonKey)
    : null

/**
 * Ensures a valid (non-expired) anonymous auth session exists.
 *
 * Three cases handled:
 *  1. No session at all → sign in anonymously.
 *  2. Session exists but access token has expired (or expires within 60 s) →
 *     refresh it. If refresh also fails (refresh token expired), sign in again.
 *  3. Session exists and token is fresh → no-op.
 *
 * Why this matters: supabase.functions.invoke sends the current access token as
 * the Authorization Bearer header. The edge function gateway verifies the JWT
 * and returns 401 if the token is missing, invalid, or expired. Checking only
 * for the presence of a session (the old behaviour) was not enough — a session
 * stored in localStorage can hold an expired access token that passes the
 * existence check but fails gateway verification.
 *
 * This function is called:
 *  - Once on mount (fire-and-forget warm-up in useEffect)
 *  - Awaited inside resolvePlace() immediately before functions.invoke, which
 *    is the only place a 401 could be observed in the Somewhere flow.
 */
export async function ensureAnonSession(): Promise<void> {
  if (!supabase) return

  const { data: { session } } = await supabase.auth.getSession()

  if (!session) {
    await supabase.auth.signInAnonymously()
    return
  }

  // Refresh if the access token has expired or will expire within 60 seconds.
  const nowSeconds = Math.floor(Date.now() / 1000)
  const expiresAt = session.expires_at ?? 0
  if (expiresAt - nowSeconds < 60) {
    const { error } = await supabase.auth.refreshSession()
    if (error) {
      // Refresh token is also expired — create a fresh anonymous session.
      await supabase.auth.signInAnonymously()
    }
  }
}

export type Confession = {
  id: string
  text: string
  lat: number | null
  lng: number | null
  created_at: string
  expires_at: string
}
