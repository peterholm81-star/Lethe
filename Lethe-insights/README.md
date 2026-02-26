# Lethe Insights

Desktop-first analytics dashboard for Lethe. Built with React + TypeScript + Vite.

## Setup

1. Copy environment variables:
   ```bash
   cp .env.local.example .env.local
   ```

2. Edit `.env.local` with your Supabase credentials:
   ```
   VITE_SUPABASE_URL=https://your-project.supabase.co
   VITE_SUPABASE_ANON_KEY=your-anon-key
   ```

3. Install dependencies and run:
   ```bash
   npm install
   npm run dev
   ```

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `VITE_SUPABASE_URL` | Yes | Supabase project URL |
| `VITE_SUPABASE_ANON_KEY` | Yes | Supabase anonymous key |
| `VITE_DEBUG_INSIGHTS` | No | Set to `true` to enable debug logging |

### Debug Logging

Debug logging is disabled by default. To enable verbose console output:

```bash
# In .env.local
VITE_DEBUG_INSIGHTS=true
```

This will log RPC calls, parameters, and responses for all metrics hooks.

## Components

- **PulseMetrics** - Sessions, readers, posts overview
- **EngagementFlow** - Funnel metrics and ad impact analysis
- **ReadersVsWriters** - Reader/writer ratio
- **IntentCard** - User intent breakdown
- **FrictionCard** - Friction points analysis
- **ChangeOverTime** - 7-day trend charts

## SQL Functions

SQL files are in `sql/` directory. Deploy to Supabase:

```bash
# Run in Supabase SQL Editor or via psql
psql < sql/get_pulse_metrics.sql
psql < sql/get_engagement_flow.sql
# etc.
```
