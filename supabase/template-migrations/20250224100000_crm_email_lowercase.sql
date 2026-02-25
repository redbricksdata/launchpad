-- Fix case-sensitive email matching in upsert_crm_contact
-- and normalize existing email data to lowercase
--
-- Problem: The RPC used `WHERE email = p_email` which is case-sensitive in
-- PostgreSQL. If a contact was imported as "Jane@Gmail.com" and then signed
-- up as "jane@gmail.com", the RPC would create a duplicate instead of merging.

-- 1. Replace the function with case-insensitive email matching
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

  -- Try to find existing contact by email first (case-insensitive), then user_id, then visitor_id
  IF p_email IS NOT NULL AND p_email <> '' THEN
    SELECT id INTO v_contact_id FROM crm_contacts WHERE LOWER(email) = LOWER(p_email) LIMIT 1;
  END IF;

  IF v_contact_id IS NULL AND p_user_id IS NOT NULL THEN
    SELECT id INTO v_contact_id FROM crm_contacts WHERE user_id = p_user_id LIMIT 1;
  END IF;

  IF v_contact_id IS NULL AND p_visitor_id IS NOT NULL AND p_visitor_id <> '' THEN
    SELECT id INTO v_contact_id FROM crm_contacts WHERE visitor_id = p_visitor_id LIMIT 1;
  END IF;

  IF v_contact_id IS NOT NULL THEN
    -- Update existing contact with any new info (emails stored lowercase)
    UPDATE crm_contacts SET
      name = COALESCE(NULLIF(p_name, ''), name),
      email = COALESCE(LOWER(NULLIF(p_email, '')), email),
      phone = COALESCE(NULLIF(p_phone, ''), phone),
      user_id = COALESCE(p_user_id, user_id),
      visitor_id = COALESCE(NULLIF(p_visitor_id, ''), visitor_id),
      last_activity = now(),
      updated_at = now()
    WHERE id = v_contact_id;
  ELSE
    -- Create new contact (email stored lowercase)
    INSERT INTO crm_contacts (name, email, phone, user_id, visitor_id, source, pipeline_stage_id)
    VALUES (p_name, LOWER(NULLIF(p_email, '')), NULLIF(p_phone, ''), p_user_id, NULLIF(p_visitor_id, ''), p_source, v_stage_id)
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

-- 2. Normalize existing emails to lowercase
UPDATE crm_contacts SET email = LOWER(email) WHERE email IS NOT NULL AND email <> LOWER(email);
