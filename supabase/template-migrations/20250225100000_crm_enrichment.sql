-- Add social profile enrichment columns to crm_contacts
--
-- Supports two free enrichment sources:
-- 1. Gravatar — avatar URL constructed from email hash (no API key needed)
-- 2. Google OAuth — avatar, name pulled from Supabase user_metadata on signup

ALTER TABLE crm_contacts
  ADD COLUMN IF NOT EXISTS avatar_url    text,
  ADD COLUMN IF NOT EXISTS job_title     text,
  ADD COLUMN IF NOT EXISTS bio           text,
  ADD COLUMN IF NOT EXISTS linkedin_url  text,
  ADD COLUMN IF NOT EXISTS social_profiles jsonb DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS enriched_at   timestamptz,
  ADD COLUMN IF NOT EXISTS enrichment_source text;
