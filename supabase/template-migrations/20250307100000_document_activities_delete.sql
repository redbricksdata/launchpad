-- ============================================================
-- Migration: Document Activities + DELETE policy
-- Items: Delete documents (#3), Audit trail (#4)
-- ============================================================

-- 1A: Add DELETE RLS policy for client_unit_documents
-- (SELECT, INSERT, UPDATE already exist; DELETE was missing)
CREATE POLICY "Clients can delete own documents"
  ON public.client_unit_documents FOR DELETE
  USING (EXISTS (
    SELECT 1 FROM public.client_units cu
    WHERE cu.id = client_unit_documents.unit_id
      AND cu.user_id = auth.uid()
  ));

-- 1B: Create document activity log table
CREATE TABLE IF NOT EXISTS public.client_unit_document_activities (
  id            bigserial PRIMARY KEY,
  document_id   uuid REFERENCES public.client_unit_documents(id) ON DELETE SET NULL,
  unit_id       uuid NOT NULL REFERENCES public.client_units(id) ON DELETE CASCADE,
  action        text NOT NULL
                CHECK (action IN ('uploaded', 'downloaded', 'viewed', 'category_changed', 'deleted')),
  actor_email   text NOT NULL,
  metadata      jsonb DEFAULT '{}',
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- 1C: Indexes
CREATE INDEX idx_doc_activities_unit
  ON public.client_unit_document_activities (unit_id, created_at DESC);

CREATE INDEX idx_doc_activities_document
  ON public.client_unit_document_activities (document_id)
  WHERE document_id IS NOT NULL;

-- 1D: RLS
ALTER TABLE public.client_unit_document_activities ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Clients can read own document activities"
  ON public.client_unit_document_activities FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM public.client_units cu
    WHERE cu.id = client_unit_document_activities.unit_id
      AND cu.user_id = auth.uid()
  ));

CREATE POLICY "Clients can insert own document activities"
  ON public.client_unit_document_activities FOR INSERT
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.client_units cu
    WHERE cu.id = client_unit_document_activities.unit_id
      AND cu.user_id = auth.uid()
  ));

CREATE POLICY "Admins can manage all document activities"
  ON public.client_unit_document_activities FOR ALL
  USING (public.is_admin());

CREATE POLICY "Service role can manage document activities"
  ON public.client_unit_document_activities FOR ALL
  USING (auth.role() = 'service_role');

-- 1E: Grants
GRANT SELECT, INSERT ON public.client_unit_document_activities TO authenticated;
GRANT ALL ON public.client_unit_document_activities TO service_role;
GRANT USAGE, SELECT ON SEQUENCE client_unit_document_activities_id_seq TO authenticated, service_role;
