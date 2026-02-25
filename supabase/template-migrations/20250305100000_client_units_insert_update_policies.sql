-- Add INSERT and UPDATE RLS policies for authenticated clients on client_units.
-- The original migration (20250304200000) only had SELECT for clients,
-- missing INSERT (needed by requestUnitAssignment) and UPDATE.

CREATE POLICY "Clients can insert own units"
  ON public.client_units FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Clients can update own units"
  ON public.client_units FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
