-- ============================================================
-- Appointment Scheduling Upgrade
-- ============================================================
-- Adds exact time slots, booking tokens for self-service,
-- blocked dates, and atomic booking RPCs.
-- ============================================================

-- ── 1. Add new columns to appointments ──────────────────────

-- Exact start/end times (new bookings use these instead of preferred_date/time)
ALTER TABLE public.appointments
  ADD COLUMN IF NOT EXISTS start_time timestamptz,
  ADD COLUMN IF NOT EXISTS end_time timestamptz;

-- Unique token for self-service manage link
ALTER TABLE public.appointments
  ADD COLUMN IF NOT EXISTS booking_token uuid UNIQUE DEFAULT gen_random_uuid();

-- Track cancellation timestamp
ALTER TABLE public.appointments
  ADD COLUMN IF NOT EXISTS cancelled_at timestamptz;

-- Link rescheduled bookings to the original
ALTER TABLE public.appointments
  ADD COLUMN IF NOT EXISTS rescheduled_from uuid REFERENCES public.appointments(id) ON DELETE SET NULL;

-- ── 2. Relax preferred_time constraint for new-style bookings ──

-- Drop the old NOT NULL + CHECK so new bookings can leave these null
ALTER TABLE public.appointments ALTER COLUMN preferred_date DROP NOT NULL;
ALTER TABLE public.appointments ALTER COLUMN preferred_time DROP NOT NULL;
ALTER TABLE public.appointments DROP CONSTRAINT IF EXISTS appointments_preferred_time_check;
-- Re-add a looser check: allow null OR the original values
ALTER TABLE public.appointments ADD CONSTRAINT appointments_preferred_time_check
  CHECK (preferred_time IS NULL OR preferred_time IN ('morning', 'afternoon', 'evening'));

-- ── 3. Backfill booking_token on existing rows ──────────────

UPDATE public.appointments
SET booking_token = gen_random_uuid()
WHERE booking_token IS NULL;

-- ── 4. Indexes for new columns ──────────────────────────────

CREATE INDEX IF NOT EXISTS idx_appointments_booking_token
  ON public.appointments (booking_token);

CREATE INDEX IF NOT EXISTS idx_appointments_start_time
  ON public.appointments (start_time)
  WHERE start_time IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_appointments_rescheduled_from
  ON public.appointments (rescheduled_from)
  WHERE rescheduled_from IS NOT NULL;

-- ── 5. Blocked dates table ──────────────────────────────────

CREATE TABLE IF NOT EXISTS public.appointment_blocked_dates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  blocked_date date NOT NULL UNIQUE,
  reason text,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.appointment_blocked_dates ENABLE ROW LEVEL SECURITY;

-- Anyone can read blocked dates (needed by public availability API)
CREATE POLICY "Anyone can read blocked dates"
  ON public.appointment_blocked_dates FOR SELECT
  USING (true);

-- Admins can manage blocked dates
CREATE POLICY "Admins can insert blocked dates"
  ON public.appointment_blocked_dates FOR INSERT
  WITH CHECK (public.is_admin());

CREATE POLICY "Admins can delete blocked dates"
  ON public.appointment_blocked_dates FOR DELETE
  USING (public.is_admin());

GRANT SELECT ON public.appointment_blocked_dates TO anon, authenticated;
GRANT INSERT, DELETE ON public.appointment_blocked_dates TO authenticated;

-- ── 6. RPC: Atomic slot booking (prevents double-booking) ───

CREATE OR REPLACE FUNCTION public.book_appointment_slot(
  p_visitor_id text,
  p_user_id uuid,
  p_name text,
  p_email text,
  p_phone text,
  p_project_id int,
  p_project_name text,
  p_floorplan_name text,
  p_appointment_type text,
  p_start_time timestamptz,
  p_end_time timestamptz,
  p_notes text,
  p_status text,
  p_rescheduled_from uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_id uuid;
  v_conflict boolean;
BEGIN
  -- Check for overlapping non-cancelled appointments
  SELECT EXISTS (
    SELECT 1 FROM public.appointments
    WHERE start_time < p_end_time
      AND end_time > p_start_time
      AND status != 'cancelled'
  ) INTO v_conflict;

  IF v_conflict THEN
    RAISE EXCEPTION 'SLOT_TAKEN';
  END IF;

  INSERT INTO public.appointments (
    visitor_id, user_id, name, email, phone,
    project_id, project_name, floorplan_name,
    appointment_type, start_time, end_time,
    notes, status, rescheduled_from
  ) VALUES (
    p_visitor_id, p_user_id, p_name, p_email, p_phone,
    p_project_id, p_project_name, p_floorplan_name,
    p_appointment_type, p_start_time, p_end_time,
    p_notes, p_status, p_rescheduled_from
  ) RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.book_appointment_slot(
  text, uuid, text, text, text, int, text, text, text,
  timestamptz, timestamptz, text, text, uuid
) TO anon, authenticated;

-- ── 7. RPC: Look up appointment by booking token ────────────

CREATE OR REPLACE FUNCTION public.get_appointment_by_token(p_token uuid)
RETURNS SETOF public.appointments
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT * FROM public.appointments WHERE booking_token = p_token LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.get_appointment_by_token(uuid) TO anon, authenticated;

-- ── 8. RPC: Cancel appointment by booking token ─────────────

CREATE OR REPLACE FUNCTION public.cancel_appointment_by_token(p_token uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.appointments
  SET status = 'cancelled',
      cancelled_at = now(),
      updated_at = now()
  WHERE booking_token = p_token
    AND status IN ('pending', 'confirmed');
  RETURN FOUND;
END;
$$;

GRANT EXECUTE ON FUNCTION public.cancel_appointment_by_token(uuid) TO anon, authenticated;
