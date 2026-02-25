-- ============================================================
-- CondoLand — Add IP Address Tracking
-- ============================================================
-- Adds ip_address column to page_views and appointments tables
-- so admins can see where visitors are connecting from.
-- ============================================================

-- ── Add ip_address to page_views ─────────────────────────────
alter table public.page_views
  add column if not exists ip_address text;

-- ── Add ip_address to appointments ───────────────────────────
alter table public.appointments
  add column if not exists ip_address text;
