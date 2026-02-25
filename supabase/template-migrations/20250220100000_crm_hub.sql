-- ================================================================
-- CRM Hub — Unified Pipeline & Contact Management
-- ================================================================
-- Consolidates leads, appointments, reminders, and drip campaigns
-- into a unified CRM system with:
--   1. Pipeline stages (customizable Kanban columns)
--   2. Contacts table (unified identity for visitors/users)
--   3. Activities timeline (chronological interaction log)
--   4. RPCs for auto-creating contacts + syncing existing leads
-- ================================================================


-- ── Table 1: Pipeline Stages ────────────────────────────────────
-- Pre-construction deal stages for Kanban board.
-- Admins can customize via UI (add/rename/reorder).
-- ──────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS crm_pipeline_stages (
  id            serial PRIMARY KEY,
  name          text NOT NULL,
  slug          text NOT NULL UNIQUE,
  sort_order    integer NOT NULL DEFAULT 0,
  color         text NOT NULL DEFAULT '#6B7280',
  is_closed     boolean NOT NULL DEFAULT false,
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- Default pre-construction stages
INSERT INTO crm_pipeline_stages (name, slug, sort_order, color, is_closed) VALUES
  ('New Lead',        'new-lead',        0, '#6366F1', false),
  ('Contacted',       'contacted',       1, '#8B5CF6', false),
  ('Appointment Set', 'appointment-set', 2, '#3B82F6', false),
  ('Unit Reserved',   'unit-reserved',   3, '#F59E0B', false),
  ('APS Signed',      'aps-signed',      4, '#10B981', false),
  ('Final Closing',   'final-closing',   5, '#059669', false),
  ('Closed Won',      'closed-won',      6, '#047857', true),
  ('Closed Lost',     'closed-lost',     7, '#EF4444', true);

ALTER TABLE crm_pipeline_stages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can manage pipeline stages"
  ON crm_pipeline_stages FOR ALL
  USING (public.is_admin());

CREATE POLICY "Service role can manage pipeline stages"
  ON crm_pipeline_stages FOR ALL
  USING (auth.role() = 'service_role');

GRANT SELECT ON crm_pipeline_stages TO authenticated;
GRANT ALL ON crm_pipeline_stages TO service_role;
GRANT USAGE, SELECT ON SEQUENCE crm_pipeline_stages_id_seq TO authenticated, service_role;


-- ── Table 2: CRM Contacts ──────────────────────────────────────
-- Unified contact record that links visitor_id + user_id.
-- Auto-created from contact forms, appointments, and lead imports.
-- ──────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS crm_contacts (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Identity (links to existing systems)
  user_id           uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  visitor_id        text,

  -- Contact info
  name              text,
  email             text,
  phone             text,
  company           text,

  -- CRM fields
  contact_type      text NOT NULL DEFAULT 'lead'
                    CHECK (contact_type IN ('lead', 'prospect', 'client', 'investor')),
  pipeline_stage_id integer NOT NULL REFERENCES crm_pipeline_stages(id) DEFAULT 1,
  source            text,
  assigned_to       text,

  -- Scoring (synced from lead scoring)
  lead_score        numeric(5,1) DEFAULT 0,

  -- Metadata
  last_activity     timestamptz DEFAULT now(),
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_crm_contacts_email ON crm_contacts (email);
CREATE INDEX idx_crm_contacts_user_id ON crm_contacts (user_id) WHERE user_id IS NOT NULL;
CREATE INDEX idx_crm_contacts_visitor_id ON crm_contacts (visitor_id) WHERE visitor_id IS NOT NULL;
CREATE INDEX idx_crm_contacts_pipeline ON crm_contacts (pipeline_stage_id);
CREATE INDEX idx_crm_contacts_type ON crm_contacts (contact_type);
CREATE INDEX idx_crm_contacts_assigned ON crm_contacts (assigned_to) WHERE assigned_to IS NOT NULL;
CREATE INDEX idx_crm_contacts_last_activity ON crm_contacts (last_activity DESC);

ALTER TABLE crm_contacts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can manage contacts"
  ON crm_contacts FOR ALL
  USING (public.is_admin());

CREATE POLICY "Service role can manage contacts"
  ON crm_contacts FOR ALL
  USING (auth.role() = 'service_role');

GRANT SELECT, INSERT, UPDATE, DELETE ON crm_contacts TO authenticated;
GRANT ALL ON crm_contacts TO service_role;


-- ── Table 3: CRM Activities ────────────────────────────────────
-- Unified timeline of all interactions for a contact.
-- ──────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS crm_activities (
  id              bigserial PRIMARY KEY,
  contact_id      uuid NOT NULL REFERENCES crm_contacts(id) ON DELETE CASCADE,
  activity_type   text NOT NULL,
  title           text NOT NULL,
  description     text,
  metadata        jsonb DEFAULT '{}',
  admin_email     text,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_crm_activities_contact ON crm_activities (contact_id, created_at DESC);
CREATE INDEX idx_crm_activities_type ON crm_activities (activity_type);

ALTER TABLE crm_activities ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can manage activities"
  ON crm_activities FOR ALL
  USING (public.is_admin());

CREATE POLICY "Service role can manage activities"
  ON crm_activities FOR ALL
  USING (auth.role() = 'service_role');

GRANT SELECT, INSERT ON crm_activities TO authenticated;
GRANT ALL ON crm_activities TO service_role;
GRANT USAGE, SELECT ON SEQUENCE crm_activities_id_seq TO authenticated, service_role;


-- ── RPC: Upsert CRM Contact ────────────────────────────────────
-- Called by contact form and appointment APIs to auto-create
-- or update a contact record, and log the activity.
--
-- Lookup priority: email → user_id → visitor_id
-- ──────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.upsert_crm_contact(
  p_name        text DEFAULT NULL,
  p_email       text DEFAULT NULL,
  p_phone       text DEFAULT NULL,
  p_visitor_id  text DEFAULT NULL,
  p_user_id     uuid DEFAULT NULL,
  p_source      text DEFAULT 'website',
  p_activity_type text DEFAULT 'manual',
  p_activity_title text DEFAULT 'Contact created'
)
RETURNS uuid AS $$
DECLARE
  v_contact_id uuid;
  v_stage_id integer;
BEGIN
  -- Get the default "New Lead" stage
  SELECT id INTO v_stage_id FROM crm_pipeline_stages WHERE slug = 'new-lead' LIMIT 1;

  -- Try to find existing contact by email first (most reliable), then user_id, then visitor_id
  IF p_email IS NOT NULL AND p_email <> '' THEN
    SELECT id INTO v_contact_id FROM crm_contacts WHERE email = p_email LIMIT 1;
  END IF;

  IF v_contact_id IS NULL AND p_user_id IS NOT NULL THEN
    SELECT id INTO v_contact_id FROM crm_contacts WHERE user_id = p_user_id LIMIT 1;
  END IF;

  IF v_contact_id IS NULL AND p_visitor_id IS NOT NULL AND p_visitor_id <> '' THEN
    SELECT id INTO v_contact_id FROM crm_contacts WHERE visitor_id = p_visitor_id LIMIT 1;
  END IF;

  IF v_contact_id IS NOT NULL THEN
    -- Update existing contact with any new info
    UPDATE crm_contacts SET
      name = COALESCE(NULLIF(p_name, ''), name),
      email = COALESCE(NULLIF(p_email, ''), email),
      phone = COALESCE(NULLIF(p_phone, ''), phone),
      user_id = COALESCE(p_user_id, user_id),
      visitor_id = COALESCE(NULLIF(p_visitor_id, ''), visitor_id),
      last_activity = now(),
      updated_at = now()
    WHERE id = v_contact_id;
  ELSE
    -- Create new contact
    INSERT INTO crm_contacts (name, email, phone, user_id, visitor_id, source, pipeline_stage_id)
    VALUES (p_name, NULLIF(p_email, ''), NULLIF(p_phone, ''), p_user_id, NULLIF(p_visitor_id, ''), p_source, v_stage_id)
    RETURNING id INTO v_contact_id;
  END IF;

  -- Log the activity
  INSERT INTO crm_activities (contact_id, activity_type, title, metadata)
  VALUES (
    v_contact_id,
    p_activity_type,
    p_activity_title,
    jsonb_build_object('source', p_source)
  );

  RETURN v_contact_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.upsert_crm_contact TO anon, authenticated, service_role;


-- ── RPC: Sync Existing Leads to CRM ────────────────────────────
-- One-time migration function that creates crm_contacts from
-- existing appointments, contact requests, and high-engagement
-- visitors. Safe to run multiple times (skips existing contacts).
-- ──────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.sync_existing_leads_to_crm()
RETURNS integer AS $$
DECLARE
  row_count integer := 0;
  v_new_lead_id integer;
  v_contacted_id integer;
  v_appt_set_id integer;
  rec record;
  v_contact_id uuid;
BEGIN
  -- Cache stage IDs
  SELECT id INTO v_new_lead_id FROM crm_pipeline_stages WHERE slug = 'new-lead';
  SELECT id INTO v_contacted_id FROM crm_pipeline_stages WHERE slug = 'contacted';
  SELECT id INTO v_appt_set_id FROM crm_pipeline_stages WHERE slug = 'appointment-set';

  -- ── Step 1: Create contacts from appointments ──────────────────
  FOR rec IN
    SELECT DISTINCT ON (COALESCE(a.email, a.visitor_id))
      a.user_id,
      a.visitor_id,
      a.name,
      a.email,
      a.phone,
      a.status,
      a.created_at
    FROM appointments a
    WHERE a.email IS NOT NULL OR a.visitor_id IS NOT NULL
    ORDER BY COALESCE(a.email, a.visitor_id), a.created_at ASC
  LOOP
    -- Skip if contact already exists
    PERFORM 1 FROM crm_contacts
    WHERE (email = rec.email AND rec.email IS NOT NULL)
       OR (visitor_id = rec.visitor_id AND rec.visitor_id IS NOT NULL);
    IF FOUND THEN CONTINUE; END IF;

    INSERT INTO crm_contacts (user_id, visitor_id, name, email, phone, source, pipeline_stage_id, last_activity, created_at)
    VALUES (
      rec.user_id,
      rec.visitor_id,
      rec.name,
      rec.email,
      rec.phone,
      'appointment',
      CASE
        WHEN rec.status IN ('completed', 'cancelled') THEN v_contacted_id
        WHEN rec.status = 'confirmed' THEN v_appt_set_id
        ELSE v_contacted_id
      END,
      rec.created_at,
      rec.created_at
    )
    RETURNING id INTO v_contact_id;

    -- Log activity
    INSERT INTO crm_activities (contact_id, activity_type, title, created_at)
    VALUES (v_contact_id, 'appointment_booked', 'Booked an appointment (imported)', rec.created_at);

    row_count := row_count + 1;
  END LOOP;

  -- ── Step 2: Create contacts from contact form submissions ──────
  FOR rec IN
    SELECT DISTINCT ON (pv.user_email)
      pv.user_id,
      pv.visitor_id,
      pv.entity_meta->>'name' AS name,
      pv.user_email AS email,
      pv.entity_meta->>'phone' AS phone,
      pv.created_at
    FROM page_views pv
    WHERE pv.entity_type = 'contact_request'
      AND pv.user_email IS NOT NULL
    ORDER BY pv.user_email, pv.created_at ASC
  LOOP
    -- Skip if contact already exists
    PERFORM 1 FROM crm_contacts
    WHERE (email = rec.email AND rec.email IS NOT NULL)
       OR (visitor_id = rec.visitor_id AND rec.visitor_id IS NOT NULL);
    IF FOUND THEN CONTINUE; END IF;

    INSERT INTO crm_contacts (user_id, visitor_id, name, email, phone, source, pipeline_stage_id, last_activity, created_at)
    VALUES (
      rec.user_id,
      rec.visitor_id,
      rec.name,
      rec.email,
      rec.phone,
      'contact_form',
      v_new_lead_id,
      rec.created_at,
      rec.created_at
    )
    RETURNING id INTO v_contact_id;

    INSERT INTO crm_activities (contact_id, activity_type, title, created_at)
    VALUES (v_contact_id, 'contact_form', 'Submitted contact form (imported)', rec.created_at);

    row_count := row_count + 1;
  END LOOP;

  -- ── Step 3: Create contacts from registered users ──────────────
  -- Pulls all auth.users who have browsing activity (page_views)
  -- but weren't already captured by appointments or contact forms.
  FOR rec IN
    SELECT DISTINCT ON (u.id)
      u.id AS user_id,
      u.email,
      u.created_at,
      pv.visitor_id,
      COALESCE(a_name.name, pv.entity_meta->>'user_name') AS name,
      COALESCE(a_phone.phone, pv.entity_meta->>'user_phone') AS phone,
      ls.last_active
    FROM auth.users u
    LEFT JOIN LATERAL (
      SELECT pv2.visitor_id, pv2.entity_meta
      FROM page_views pv2
      WHERE pv2.user_id = u.id
      ORDER BY pv2.created_at DESC
      LIMIT 1
    ) pv ON true
    LEFT JOIN LATERAL (
      SELECT a2.name
      FROM appointments a2
      WHERE a2.user_id = u.id OR a2.email = u.email
      ORDER BY a2.created_at DESC
      LIMIT 1
    ) a_name ON true
    LEFT JOIN LATERAL (
      SELECT a3.phone
      FROM appointments a3
      WHERE (a3.user_id = u.id OR a3.email = u.email) AND a3.phone IS NOT NULL
      ORDER BY a3.created_at DESC
      LIMIT 1
    ) a_phone ON true
    LEFT JOIN LATERAL (
      SELECT MAX(pv3.created_at) AS last_active
      FROM page_views pv3
      WHERE pv3.user_id = u.id
    ) ls ON true
    ORDER BY u.id, u.created_at
  LOOP
    -- Skip if contact already exists (by email or user_id)
    PERFORM 1 FROM crm_contacts
    WHERE (email = rec.email AND rec.email IS NOT NULL)
       OR (user_id = rec.user_id);
    IF FOUND THEN
      -- Still link user_id if it wasn't linked before
      UPDATE crm_contacts SET
        user_id = COALESCE(crm_contacts.user_id, rec.user_id),
        name = COALESCE(crm_contacts.name, rec.name),
        phone = COALESCE(crm_contacts.phone, rec.phone)
      WHERE (email = rec.email OR user_id = rec.user_id)
        AND (crm_contacts.user_id IS NULL OR crm_contacts.name IS NULL);
      CONTINUE;
    END IF;

    INSERT INTO crm_contacts (user_id, visitor_id, name, email, phone, source, pipeline_stage_id, last_activity, created_at)
    VALUES (
      rec.user_id,
      rec.visitor_id,
      rec.name,
      rec.email,
      rec.phone,
      'registration',
      v_new_lead_id,
      COALESCE(rec.last_active, rec.created_at),
      rec.created_at
    )
    RETURNING id INTO v_contact_id;

    INSERT INTO crm_activities (contact_id, activity_type, title, created_at)
    VALUES (v_contact_id, 'manual', 'User registered (imported)', rec.created_at);

    row_count := row_count + 1;
  END LOOP;

  -- ── Step 4: Create contacts from chat conversations ────────────
  FOR rec IN
    SELECT DISTINCT ON (COALESCE(cc.visitor_email, cc.visitor_id))
      cc.user_id,
      cc.visitor_id,
      cc.visitor_name AS name,
      cc.visitor_email AS email,
      cc.visitor_phone AS phone,
      cc.created_at
    FROM chat_conversations cc
    WHERE cc.visitor_email IS NOT NULL OR cc.visitor_id IS NOT NULL
    ORDER BY COALESCE(cc.visitor_email, cc.visitor_id), cc.created_at ASC
  LOOP
    PERFORM 1 FROM crm_contacts
    WHERE (email = rec.email AND rec.email IS NOT NULL)
       OR (visitor_id = rec.visitor_id AND rec.visitor_id IS NOT NULL);
    IF FOUND THEN CONTINUE; END IF;

    INSERT INTO crm_contacts (user_id, visitor_id, name, email, phone, source, pipeline_stage_id, last_activity, created_at)
    VALUES (
      rec.user_id,
      rec.visitor_id,
      rec.name,
      rec.email,
      rec.phone,
      'live_chat',
      v_new_lead_id,
      rec.created_at,
      rec.created_at
    )
    RETURNING id INTO v_contact_id;

    INSERT INTO crm_activities (contact_id, activity_type, title, created_at)
    VALUES (v_contact_id, 'contact_form', 'Started live chat (imported)', rec.created_at);

    row_count := row_count + 1;
  END LOOP;

  -- ── Step 5: Create contacts from high-engagement visitors ──────
  -- Anonymous visitors with engagement score > 15 who weren't captured above.
  FOR rec IN
    SELECT
      ls.identifier,
      ls.user_id,
      ls.email,
      ls.display_name AS name,
      ls.phone,
      ls.score,
      ls.last_active
    FROM get_lead_scores() ls
    WHERE ls.score > 15
    ORDER BY ls.score DESC
  LOOP
    -- Skip if already in CRM
    PERFORM 1 FROM crm_contacts
    WHERE (email = rec.email AND rec.email IS NOT NULL)
       OR (user_id = rec.user_id AND rec.user_id IS NOT NULL)
       OR (visitor_id = rec.identifier AND rec.identifier IS NOT NULL);
    IF FOUND THEN
      -- Update lead score on existing contact
      UPDATE crm_contacts SET
        lead_score = GREATEST(crm_contacts.lead_score, rec.score)
      WHERE (email = rec.email AND rec.email IS NOT NULL)
         OR (user_id = rec.user_id AND rec.user_id IS NOT NULL)
         OR (visitor_id = rec.identifier);
      CONTINUE;
    END IF;

    INSERT INTO crm_contacts (
      user_id, visitor_id, name, email, phone, source,
      pipeline_stage_id, lead_score, last_activity, created_at
    )
    VALUES (
      rec.user_id,
      CASE WHEN rec.user_id IS NULL THEN rec.identifier ELSE NULL END,
      rec.name,
      rec.email,
      rec.phone,
      'high_engagement',
      v_new_lead_id,
      rec.score,
      rec.last_active,
      COALESCE(rec.last_active, now())
    )
    RETURNING id INTO v_contact_id;

    INSERT INTO crm_activities (contact_id, activity_type, title, created_at)
    VALUES (v_contact_id, 'manual', 'High-engagement visitor imported (score: ' || round(rec.score) || ')', COALESCE(rec.last_active, now()));

    row_count := row_count + 1;
  END LOOP;

  RETURN row_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.sync_existing_leads_to_crm TO authenticated, service_role;


-- ── RPC: Get CRM Pipeline Summary ──────────────────────────────
-- Returns contact counts per pipeline stage for the dashboard.
-- ──────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_crm_pipeline_summary()
RETURNS TABLE (
  stage_id integer,
  stage_name text,
  stage_slug text,
  stage_color text,
  sort_order integer,
  is_closed boolean,
  contact_count bigint
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    ps.id,
    ps.name,
    ps.slug,
    ps.color,
    ps.sort_order,
    ps.is_closed,
    count(cc.id)::bigint
  FROM crm_pipeline_stages ps
  LEFT JOIN crm_contacts cc ON cc.pipeline_stage_id = ps.id
  GROUP BY ps.id, ps.name, ps.slug, ps.color, ps.sort_order, ps.is_closed
  ORDER BY ps.sort_order;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

GRANT EXECUTE ON FUNCTION public.get_crm_pipeline_summary TO authenticated;
