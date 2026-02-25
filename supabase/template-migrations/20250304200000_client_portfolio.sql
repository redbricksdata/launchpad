-- ============================================================
-- Client Portfolio: units, deposits, documents, actions,
-- collaborators, storage bucket, notification types
-- ============================================================

-- 1. client_units — core portfolio table
CREATE TABLE IF NOT EXISTS public.client_units (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  contact_id        uuid REFERENCES public.crm_contacts(id) ON DELETE SET NULL,
  project_id        integer NOT NULL,
  project_name      text NOT NULL,
  floorplan_id      integer,
  floorplan_name    text,
  unit_number       text,
  floor             text,
  exposure          text,
  purchase_price    numeric,
  purchase_date     date,
  purchase_psf      numeric,
  status            text NOT NULL DEFAULT 'active'
                    CHECK (status IN ('active', 'pending_assignment', 'sold', 'leased')),
  construction_stage text
                    CHECK (construction_stage IS NULL OR construction_stage IN (
                      'pre_construction', 'excavation', 'foundation',
                      'structure', 'envelope', 'interior', 'occupancy'
                    )),
  last_checked_price numeric,
  last_price_check   timestamptz,
  notes             text,
  assigned_by       text,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_client_units_user ON public.client_units (user_id) WHERE user_id IS NOT NULL;
CREATE INDEX idx_client_units_contact ON public.client_units (contact_id) WHERE contact_id IS NOT NULL;
CREATE INDEX idx_client_units_project ON public.client_units (project_id);
CREATE INDEX idx_client_units_status ON public.client_units (status);

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION public.update_client_units_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_client_units_updated_at
  BEFORE UPDATE ON public.client_units
  FOR EACH ROW EXECUTE FUNCTION public.update_client_units_updated_at();

-- RLS
ALTER TABLE public.client_units ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Clients can read own units"
  ON public.client_units FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Admins can manage all units"
  ON public.client_units FOR ALL
  USING (public.is_admin());

CREATE POLICY "Service role can manage units"
  ON public.client_units FOR ALL
  USING (auth.role() = 'service_role');


-- 2. client_unit_deposits — deposit tracking per unit
CREATE TABLE IF NOT EXISTS public.client_unit_deposits (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  unit_id       uuid NOT NULL REFERENCES public.client_units(id) ON DELETE CASCADE,
  deposit_name  text NOT NULL,
  amount        numeric NOT NULL,
  due_date      date NOT NULL,
  paid          boolean NOT NULL DEFAULT false,
  paid_date     date,
  reminder_sent_at timestamptz,
  notes         text,
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_client_unit_deposits_unit ON public.client_unit_deposits (unit_id);
CREATE INDEX idx_client_unit_deposits_due ON public.client_unit_deposits (due_date) WHERE paid = false;

ALTER TABLE public.client_unit_deposits ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Clients can read own deposits"
  ON public.client_unit_deposits FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM public.client_units cu
    WHERE cu.id = client_unit_deposits.unit_id
    AND cu.user_id = auth.uid()
  ));

CREATE POLICY "Clients can update own deposits"
  ON public.client_unit_deposits FOR UPDATE
  USING (EXISTS (
    SELECT 1 FROM public.client_units cu
    WHERE cu.id = client_unit_deposits.unit_id
    AND cu.user_id = auth.uid()
  ));

CREATE POLICY "Admins can manage all deposits"
  ON public.client_unit_deposits FOR ALL
  USING (public.is_admin());

CREATE POLICY "Service role can manage deposits"
  ON public.client_unit_deposits FOR ALL
  USING (auth.role() = 'service_role');


-- 3. client_unit_documents — document vault per unit
CREATE TABLE IF NOT EXISTS public.client_unit_documents (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  unit_id       uuid NOT NULL REFERENCES public.client_units(id) ON DELETE CASCADE,
  file_name     text NOT NULL,
  file_path     text NOT NULL,
  file_size     integer NOT NULL,
  file_type     text NOT NULL,
  category      text NOT NULL DEFAULT 'other'
                CHECK (category IN (
                  'purchase_agreement', 'amendment', 'receipt',
                  'insurance', 'closing', 'other'
                )),
  uploaded_by   text NOT NULL,
  notes         text,
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_client_unit_documents_unit ON public.client_unit_documents (unit_id);

ALTER TABLE public.client_unit_documents ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Clients can read own documents"
  ON public.client_unit_documents FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM public.client_units cu
    WHERE cu.id = client_unit_documents.unit_id
    AND cu.user_id = auth.uid()
  ));

CREATE POLICY "Clients can insert own documents"
  ON public.client_unit_documents FOR INSERT
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.client_units cu
    WHERE cu.id = client_unit_documents.unit_id
    AND cu.user_id = auth.uid()
  ));

CREATE POLICY "Admins can manage all documents"
  ON public.client_unit_documents FOR ALL
  USING (public.is_admin());

CREATE POLICY "Service role can manage documents"
  ON public.client_unit_documents FOR ALL
  USING (auth.role() = 'service_role');


-- 4. client_unit_actions — action requests (assign/sell/lease/question)
CREATE TABLE IF NOT EXISTS public.client_unit_actions (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  unit_id       uuid NOT NULL REFERENCES public.client_units(id) ON DELETE CASCADE,
  user_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  action_type   text NOT NULL
                CHECK (action_type IN ('assign', 'sell', 'lease', 'question')),
  message       text,
  status        text NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending', 'in_progress', 'completed', 'cancelled')),
  admin_notes   text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_client_unit_actions_unit ON public.client_unit_actions (unit_id);
CREATE INDEX idx_client_unit_actions_user ON public.client_unit_actions (user_id);
CREATE INDEX idx_client_unit_actions_pending ON public.client_unit_actions (status) WHERE status = 'pending';

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION public.update_client_unit_actions_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_client_unit_actions_updated_at
  BEFORE UPDATE ON public.client_unit_actions
  FOR EACH ROW EXECUTE FUNCTION public.update_client_unit_actions_updated_at();

ALTER TABLE public.client_unit_actions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Clients can read own actions"
  ON public.client_unit_actions FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Clients can insert own actions"
  ON public.client_unit_actions FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Admins can manage all actions"
  ON public.client_unit_actions FOR ALL
  USING (public.is_admin());

CREATE POLICY "Service role can manage actions"
  ON public.client_unit_actions FOR ALL
  USING (auth.role() = 'service_role');


-- 5. client_unit_collaborators — shared access for brokers/lawyers
CREATE TABLE IF NOT EXISTS public.client_unit_collaborators (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  unit_id         uuid NOT NULL REFERENCES public.client_units(id) ON DELETE CASCADE,
  invited_by      uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  email           text NOT NULL,
  name            text,
  role            text NOT NULL DEFAULT 'other'
                  CHECK (role IN ('lawyer', 'mortgage_broker', 'accountant', 'other')),
  access_token    uuid NOT NULL UNIQUE DEFAULT gen_random_uuid(),
  permissions     text NOT NULL DEFAULT 'view_and_upload'
                  CHECK (permissions IN ('view_and_upload', 'view_only')),
  status          text NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending', 'active', 'revoked')),
  last_accessed_at timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_client_unit_collaborators_unit ON public.client_unit_collaborators (unit_id);
CREATE INDEX idx_client_unit_collaborators_token ON public.client_unit_collaborators (access_token);
CREATE INDEX idx_client_unit_collaborators_email ON public.client_unit_collaborators (email);

ALTER TABLE public.client_unit_collaborators ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Clients can manage own collaborators"
  ON public.client_unit_collaborators FOR ALL
  USING (EXISTS (
    SELECT 1 FROM public.client_units cu
    WHERE cu.id = client_unit_collaborators.unit_id
    AND cu.user_id = auth.uid()
  ));

CREATE POLICY "Admins can manage all collaborators"
  ON public.client_unit_collaborators FOR ALL
  USING (public.is_admin());

CREATE POLICY "Service role can manage collaborators"
  ON public.client_unit_collaborators FOR ALL
  USING (auth.role() = 'service_role');

-- Anon/public SELECT for token-based portal access
CREATE POLICY "Public can read by access token"
  ON public.client_unit_collaborators FOR SELECT
  USING (true);


-- 6. Storage bucket: client-documents (private)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'client-documents',
  'client-documents',
  false,
  26214400,  -- 25MB
  ARRAY[
    'application/pdf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'image/png',
    'image/jpeg'
  ]
)
ON CONFLICT (id) DO NOTHING;

-- Clients read own docs (path: {userId}/{unitId}/*)
CREATE POLICY "Client read own client-documents"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'client-documents'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Clients upload own docs
CREATE POLICY "Client upload own client-documents"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'client-documents'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Clients delete own docs
CREATE POLICY "Client delete own client-documents"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'client-documents'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Admins manage all client-documents
CREATE POLICY "Admin manage all client-documents"
  ON storage.objects FOR ALL
  TO authenticated
  USING (
    bucket_id = 'client-documents'
    AND public.is_admin()
  );

-- Anon/public can upload to collaborator paths (token verified in API)
CREATE POLICY "Public upload client-documents via collaborator"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'client-documents'
    AND (storage.foldername(name))[1] = 'collaborator'
  );

-- Public can read collaborator-uploaded docs (access controlled via API signed URLs)
CREATE POLICY "Public read collaborator client-documents"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'client-documents'
    AND (storage.foldername(name))[1] = 'collaborator'
  );


-- 7. Expand notification types
DO $$
DECLARE
  _constraint_name text;
BEGIN
  SELECT con.conname INTO _constraint_name
  FROM pg_constraint con
  JOIN pg_class rel ON rel.oid = con.conrelid
  JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
  WHERE rel.relname = 'notifications'
    AND nsp.nspname = 'public'
    AND con.contype = 'c'
    AND pg_get_constraintdef(con.oid) ILIKE '%type%';

  IF _constraint_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.notifications DROP CONSTRAINT %I', _constraint_name);
  END IF;
END $$;

ALTER TABLE public.notifications
  ADD CONSTRAINT chk_notifications_type
  CHECK (type IN (
    'price_drop', 'price_increase', 'status_change',
    'new_floorplans', 'floorplan_updated', 'new_project',
    'saved_search_match', 'chat_reply', 'appointment_reminder',
    'welcome', 'general',
    'deposit_reminder', 'price_update', 'construction_milestone',
    'document_uploaded', 'unit_assigned'
  ));


-- 8. Add portfolio_alerts to email_preferences
ALTER TABLE public.email_preferences
  ADD COLUMN IF NOT EXISTS portfolio_alerts boolean DEFAULT true;


-- 9. RPC: auto-import deposit schedule from project data
CREATE OR REPLACE FUNCTION public.import_deposit_schedule(
  p_unit_id uuid,
  p_deposit_data jsonb
) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_count integer := 0;
  v_item jsonb;
BEGIN
  IF p_deposit_data IS NULL OR jsonb_typeof(p_deposit_data) != 'array' OR jsonb_array_length(p_deposit_data) = 0 THEN
    RETURN 0;
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_deposit_data)
  LOOP
    INSERT INTO public.client_unit_deposits (unit_id, deposit_name, amount, due_date)
    VALUES (
      p_unit_id,
      COALESCE(v_item->>'label', v_item->>'name', 'Deposit'),
      COALESCE((v_item->>'deposit_amount')::numeric, (v_item->>'amount')::numeric, 0),
      COALESCE(
        (v_item->>'deposit_due_on')::date,
        (v_item->>'due_date')::date,
        CURRENT_DATE + interval '30 days' * (v_count + 1)
      )
    );
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;
