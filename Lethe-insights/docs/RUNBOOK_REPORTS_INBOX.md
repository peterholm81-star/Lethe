# Reports Inbox - Deployment Runbook

## Overview

Reports Inbox (Moderation v2) allows admins to:
- View reported confessions **grouped by confession** (anti-chaos)
- See aggregated stats: total reports, reasons breakdown, timestamps
- Mark ALL reports for a confession as handled/unhandled
- Hide/unhide confessions from public feeds

## Prerequisites

1. You must be in `admin_users` table
2. Anonymous auth must be enabled in Supabase
3. `is_admin()` function must exist (from `reports_inbox_setup.sql`)

---

## SQL Deployment Steps

Run these files in **Supabase SQL Editor** in order:

### Step 1: `sql/confession_set_hidden.sql`

Creates `set_confession_hidden(p_confession_id, p_hidden)` RPC.

```sql
-- Verify function exists:
SELECT proname FROM pg_proc WHERE proname = 'set_confession_hidden';
```

### Step 2: `sql/reports_groups_get.sql` (NEW - v2)

Creates `get_reports_groups(p_limit, p_only_unhandled)` RPC - grouped view.

```sql
-- Verify after running:
SELECT * FROM public.get_reports_groups(10, true);
```

### Step 3: `sql/reports_groups_set_handled.sql` (NEW - v2)

Creates `set_reports_handled_for_confession(p_confession_id, p_handled)` RPC.

```sql
-- Verify function exists:
SELECT proname FROM pg_proc WHERE proname = 'set_reports_handled_for_confession';
```

### Legacy (Optional - v1)

These are no longer used by the UI but can remain:
- `sql/reports_inbox_get.sql` - `get_reports_inbox`
- `sql/reports_set_handled.sql` - `set_report_handled`

---

## Frontend Files

No deployment needed - these are built into the app:

- `src/hooks/useReportsInbox.ts` - Data fetching hook
- `src/pages/ReportsPage.tsx` - UI component

---

## Testing Checklist (v2 - Grouped View)

### 1. Open Reports Inbox
- [ ] Navigate to Insights → Reports in sidebar
- [ ] Page loads without "Admin only" error
- [ ] Shows "No unhandled reports" or list of **grouped** confessions

### 2. Verify Grouped View
- [ ] Each row = 1 confession (not 1 report)
- [ ] Shows "Reports" column with total count
- [ ] Shows "Reasons" column with breakdown badges (e.g. SPAM:3, THREATS:1)
- [ ] Shows first/last reported timestamps

### 3. Filter Toggle
- [ ] Click "Unhandled" - shows only confessions with unhandled reports
- [ ] Click "All" - shows all confessions with reports
- [ ] Stats update: "X confessions with Y total reports"

### 4. View Confession Details
- [ ] Click "View" or confession text to open modal
- [ ] Modal shows: total reports, unhandled count, first/last reported
- [ ] Modal shows reasons breakdown (all reasons with counts)
- [ ] Modal shows full confession text
- [ ] Modal shows status: All Handled? + Hidden?

### 5. Mark All Handled (Group)
- [ ] Click "Handle" on a group with unhandled reports
- [ ] Button disables during action
- [ ] Toast shows "Marked X report(s) as handled"
- [ ] Group moves to "Handled" status
- [ ] If filter is "Unhandled", group disappears from list

### 6. Undo All Handled (Group)
- [ ] Switch filter to "All"
- [ ] Click "Undo" on a fully handled group
- [ ] Toast shows "Unmarked X report(s)"
- [ ] Group returns to "Open" status

### 7. Hide Confession
- [ ] Click "Hide" on a group with visible confession
- [ ] Toast shows "Confession hidden"
- [ ] All reports marked as handled automatically
- [ ] Confession badge changes to "Hidden"

### 8. Unhide Confession
- [ ] Click "Unhide" on a group with hidden confession
- [ ] Toast shows "Confession unhidden"
- [ ] Confession badge changes to "Visible"

### 9. Verify Confession Hidden in App
- [ ] Open main Lethe app
- [ ] Confirm hidden confession doesn't appear in World/Near Me feeds

---

## Troubleshooting

### "Admin only" error
1. Check your user_id: Look at console logs for `[INSIGHTS][AUTH] user.id`
2. Add to admin_users:
   ```sql
   INSERT INTO admin_users (user_id) VALUES ('your-uid-here');
   ```

### "column c.xxx does not exist"
1. Schema mismatch - verify `confessions` table columns:
   ```sql
   SELECT column_name FROM information_schema.columns 
   WHERE table_name = 'confessions';
   ```
2. Re-run `sql/reports_inbox_get.sql` with correct column names

### Actions fail silently
1. Check browser console for errors
2. Verify RPC functions exist:
   ```sql
   SELECT proname FROM pg_proc 
   WHERE proname IN ('set_report_handled', 'set_confession_hidden');
   ```

---

## Schema Reference

### confession_reports
```
id uuid PK
confession_id uuid FK
reason text
details text
city_code text
handled boolean
handled_at timestamptz
handled_by uuid
action_taken text
created_at timestamptz
```

### confessions (relevant columns)
```
id uuid PK
text text          -- confession content
region text        -- location/region
is_hidden boolean  -- moderation flag
```
