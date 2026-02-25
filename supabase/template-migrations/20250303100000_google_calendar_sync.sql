-- ============================================================
-- Google Calendar 2-Way Sync
-- ============================================================
-- Adds google_event_id tracking on appointments and a busy-time
-- cache table that the availability engine reads from.
-- ============================================================

-- 1. Add google_event_id to appointments table
ALTER TABLE public.appointments
  ADD COLUMN IF NOT EXISTS google_event_id text;

CREATE INDEX IF NOT EXISTS idx_appointments_google_event_id
  ON public.appointments (google_event_id)
  WHERE google_event_id IS NOT NULL;

-- 2. Google Calendar busy-time cache
-- Populated by cron (every 5 min), read by the availability API.
CREATE TABLE IF NOT EXISTS public.google_calendar_busy_cache (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  integration_id uuid NOT NULL REFERENCES public.crm_integrations(id) ON DELETE CASCADE,
  busy_start timestamptz NOT NULL,
  busy_end timestamptz NOT NULL,
  fetched_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_gcal_busy_range
  ON public.google_calendar_busy_cache (integration_id, busy_start, busy_end);

-- RLS: public read (availability API needs it), authenticated write
ALTER TABLE public.google_calendar_busy_cache ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read busy cache"
  ON public.google_calendar_busy_cache
  FOR SELECT USING (true);

CREATE POLICY "Authenticated can manage busy cache"
  ON public.google_calendar_busy_cache
  FOR ALL
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

GRANT SELECT ON public.google_calendar_busy_cache TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.google_calendar_busy_cache TO authenticated;
