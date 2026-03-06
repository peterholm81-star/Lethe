# Dev Bundle Checklist — Lethe Insights

What to bring from your old PC vs. what's already in the repo.

---

## Already in Git (no action needed)

- [x] Source code (`src/`, `public/`, `sql/`, `docs/`)
- [x] Config files (`package.json`, `tsconfig*.json`, `vite.config.ts`, `eslint.config.js`)
- [x] Lock file (`package-lock.json`)
- [x] `.env.example` (template)
- [x] Supabase migrations (`../supabase/migrations/`)

## Must Copy from Old PC

These files are **gitignored** and contain secrets:

- [ ] `.env.local` — Supabase URL, anon key, Mapbox token
- [ ] Any local Supabase config (if using `supabase` CLI locally): `../supabase/.temp/`

### How to copy

Easiest: copy `.env.local` to a USB stick or use a secure transfer tool.
Or run the bundle script from your old PC:

```powershell
.\scripts\make-dev-bundle.ps1     # Creates lethe-dev-bundle.zip
```

Then on the new PC, extract and copy `.env.local` into `Lethe-insights/`.

## Must NEVER Be Committed

| File / Value | Why |
|---|---|
| `.env.local` | Contains Supabase anon key and Mapbox token |
| `.env` | Gitignored — runtime secrets |
| Supabase **service-role key** | Full DB access — never expose client-side |
| Mapbox **secret token** (sk.*) | Server-only; the public token (pk.*) is fine for `.env.local` |

## If You Forgot Your Secrets

| Secret | Where to find it |
|--------|-----------------|
| `VITE_SUPABASE_URL` | [Supabase Dashboard](https://supabase.com/dashboard) → your project → Settings → API → Project URL |
| `VITE_SUPABASE_ANON_KEY` | Same page → anon / public key |
| `VITE_MAPBOX_TOKEN` | [Mapbox Account](https://account.mapbox.com/access-tokens/) → copy default public token or create a new one |

> **Tip:** Bookmark these two dashboards on your new PC. You'll need them again.

## Quick Verification After Setup

```powershell
.\scripts\doctor.ps1               # Checks tools + env vars
npm run dev                        # Should start without errors
# Open http://localhost:5173       # Verify data loads + map renders
```
