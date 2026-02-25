-- =============================================================
-- Portfolio: parking/locker columns, archived status, doc policy
-- =============================================================

-- 1A: Fix status CHECK constraint to include 'archived'
DO $$ DECLARE _c text;
BEGIN
  SELECT con.conname INTO _c
  FROM pg_constraint con
  JOIN pg_class rel ON rel.oid = con.conrelid
  JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
  WHERE rel.relname = 'client_units'
    AND nsp.nspname = 'public'
    AND con.contype = 'c'
    AND pg_get_constraintdef(con.oid) ILIKE '%status%';
  IF _c IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.client_units DROP CONSTRAINT %I', _c);
  END IF;
END $$;

ALTER TABLE public.client_units
  ADD CONSTRAINT chk_client_units_status
  CHECK (status IN ('active', 'pending_assignment', 'sold', 'leased', 'archived'));

-- 1B: Add parking/locker columns
ALTER TABLE public.client_units
  ADD COLUMN IF NOT EXISTS parking_spots smallint NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS locker_count smallint NOT NULL DEFAULT 0;

-- 1C: RLS UPDATE policy for client documents (needed for category editing)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'client_unit_documents'
      AND policyname = 'Clients can update own documents'
  ) THEN
    CREATE POLICY "Clients can update own documents"
      ON public.client_unit_documents FOR UPDATE
      USING (EXISTS (
        SELECT 1 FROM public.client_units cu
        WHERE cu.id = client_unit_documents.unit_id
        AND cu.user_id = auth.uid()
      ));
  END IF;
END $$;
