-- ============================================================
-- Add 'new_registration' as a drip sequence trigger type
-- ============================================================

alter table public.drip_sequences
  drop constraint if exists drip_sequences_trigger_type_check;

alter table public.drip_sequences
  add constraint drip_sequences_trigger_type_check
  check (trigger_type in (
    'appointment_booked', 'contact_request', 'project_favorited',
    'high_engagement', 'new_registration'
  ));
