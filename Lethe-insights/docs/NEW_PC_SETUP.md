# New PC Setup — Lethe Insights

Get the dev environment running on a fresh machine in ~10 minutes.

---

## 1. Prerequisites (Windows / PowerShell)

| Tool | Install | Verify |
|------|---------|--------|
| **Node.js LTS** (≥ 20) | https://nodejs.org or `winget install OpenJS.NodeJS.LTS` | `node -v` |
| **Git** | https://git-scm.com or `winget install Git.Git` | `git --version` |
| **Cursor** | https://cursor.com/download | Open the app |
| **Supabase CLI** (optional) | `npm i -g supabase` | `supabase --version` |

> Restart your terminal after installing Node/Git so PATH updates take effect.

## 2. Clone & Install

```powershell
git clone https://github.com/YOUR_ORG/Confess.git
cd Confess\Lethe-insights
npm install
```

## 3. Environment Variables

```powershell
Copy-Item .env.example .env.local
```

Open `.env.local` and fill in the three required values:

| Variable | Where to find it |
|----------|-----------------|
| `VITE_SUPABASE_URL` | Supabase Dashboard → Settings → API → Project URL |
| `VITE_SUPABASE_ANON_KEY` | Supabase Dashboard → Settings → API → anon / public key |
| `VITE_MAPBOX_TOKEN` | https://account.mapbox.com/access-tokens/ |

## 4. Start Dev Server

```powershell
npm run dev
```

Open [http://localhost:5173](http://localhost:5173) in your browser.

## 5. Other Commands

```powershell
npm run build       # Production build (runs tsc + vite build)
npm run lint        # ESLint
npm run preview     # Serve production build locally
```

## 6. Verify Supabase Connection

1. Open the app in browser.
2. Open DevTools → Console.
3. You should see RPC calls to your Supabase URL without 401/403 errors.
4. If you see `FetchError` or `Invalid API key`: double-check `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` in `.env.local`.

## 7. Verify Mapbox Loads

1. Navigate to a page with a map (e.g. Reports or Monetization).
2. You should see a dark-themed Mapbox map rendering.
3. If blank or "Mapbox token invalid": check `VITE_MAPBOX_TOKEN` in `.env.local`.
4. Ensure the token has the `styles:read` and `fonts:read` scopes at https://account.mapbox.com.

## 8. Run the Doctor Script

```powershell
.\scripts\doctor.ps1
```

This checks Node, npm, Git, Supabase CLI versions and validates your `.env.local`.

---

## Mac / Linux

Same steps, except:

```bash
# Install Node via nvm (recommended)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash
nvm install --lts

# Clone
git clone https://github.com/YOUR_ORG/Confess.git
cd Confess/Lethe-insights
npm install

# Env
cp .env.example .env.local
# Edit .env.local with your editor

# Dev
npm run dev

# Doctor
chmod +x scripts/doctor.sh && ./scripts/doctor.sh
```

---

## Common Errors + Fixes

### Port 5173 already in use

```powershell
# Find and kill the process
netstat -ano | findstr :5173
taskkill /PID <PID> /F
# Or just change port: npm run dev -- --port 5174
```

### Missing environment variables

```
Error: supabaseUrl is required
```

You forgot to create `.env.local` or left placeholder values. See step 3.

### Wrong Node version

```
npm warn EBADENGINE
```

Upgrade to Node LTS (≥ 20): `nvm install --lts` or download from nodejs.org.

### Supabase auth errors (401 / 403)

- Verify `VITE_SUPABASE_ANON_KEY` is the **anon** key, not the service-role key.
- Check that RLS policies are deployed (see `sql/` folder for migration scripts).

### TypeScript errors on build

```powershell
npx tsc --noEmit    # Check without building
```

If errors appear after pulling, run `npm install` first — a dependency may have changed.
