-- ============================================================
-- Enhanced Intent Signals — Trending + Lead Scoring
-- ============================================================
-- Adds 5 new tracking signals: search, compare, calculator, pdf, chat
-- Adds dwell_seconds column to page_views for time-on-page weighting
-- Recreates get_trending_projects() and get_lead_scores() with all 12 signals
-- ============================================================

-- ── 1. Add dwell_seconds column to page_views ────────────────
ALTER TABLE page_views ADD COLUMN IF NOT EXISTS dwell_seconds INT;

-- ── 1b. Update CHECK constraint to allow new entity types ────
-- Drop old constraint (if it exists) and add new one with all 10 types
DO $$
BEGIN
  -- Try dropping by the most common constraint name patterns
  BEGIN
    ALTER TABLE page_views DROP CONSTRAINT IF EXISTS page_views_entity_type_check;
  EXCEPTION WHEN undefined_object THEN NULL;
  END;
  -- Also try the unnamed check constraint approach
  BEGIN
    EXECUTE (
      SELECT 'ALTER TABLE page_views DROP CONSTRAINT ' || quote_ident(conname)
      FROM pg_constraint
      WHERE conrelid = 'page_views'::regclass
        AND contype = 'c'
        AND pg_get_constraintdef(oid) LIKE '%entity_type%'
      LIMIT 1
    );
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
END $$;

ALTER TABLE page_views ADD CONSTRAINT page_views_entity_type_check
  CHECK (entity_type IN (
    'project', 'floorplan', 'contact_request', 'share', 'appointment',
    'search', 'calculator', 'pdf', 'compare', 'chat'
  ));

-- ── 2. Dwell time multiplier function ─────────────────────────
CREATE OR REPLACE FUNCTION public.dwell_multiplier(seconds INT)
RETURNS NUMERIC AS $$
BEGIN
  IF seconds IS NULL THEN RETURN 1.0; END IF;
  IF seconds < 5 THEN RETURN 0.1; END IF;
  IF seconds <= 30 THEN RETURN 1.0; END IF;
  IF seconds <= 120 THEN RETURN 2.0; END IF;
  RETURN 3.0;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ── 3. Recreate get_trending_projects with all 12 signals ─────
DROP FUNCTION IF EXISTS public.get_trending_projects(int, int);

CREATE OR REPLACE FUNCTION public.get_trending_projects(
  result_limit int default 10,
  window_days int default 30
)
RETURNS TABLE (
  entity_id int,
  entity_name text,
  score numeric,
  view_count bigint,
  like_count bigint,
  save_count bigint,
  share_count bigint,
  contact_count bigint,
  appointment_count bigint,
  search_count bigint,
  compare_count bigint,
  calculator_count bigint,
  pdf_count bigint,
  chat_count bigint
) AS $$
BEGIN
  RETURN QUERY
  WITH
    cutoff AS (
      SELECT now() - (window_days || ' days')::interval AS since
    ),

    -- ── Page views (weight: 1, dwell-weighted) ──────────────
    views AS (
      SELECT
        pv.entity_id,
        pv.entity_name,
        count(*) AS cnt,
        sum(
          exp(-3.0 * extract(epoch FROM (now() - pv.created_at)) / (window_days * 86400))
          * dwell_multiplier(pv.dwell_seconds)
        ) AS weighted
      FROM page_views pv, cutoff c
      WHERE pv.entity_type = 'project'
        AND pv.entity_id IS NOT NULL
        AND pv.created_at >= c.since
      GROUP BY pv.entity_id, pv.entity_name
    ),

    -- ── Floorplan views aggregated to project (weight: 2, dwell-weighted) ──
    floorplan_views AS (
      SELECT
        (pv.entity_meta->>'project_id')::int AS entity_id,
        count(*) AS cnt,
        sum(
          exp(-3.0 * extract(epoch FROM (now() - pv.created_at)) / (window_days * 86400))
          * dwell_multiplier(pv.dwell_seconds)
        ) AS weighted
      FROM page_views pv, cutoff c
      WHERE pv.entity_type = 'floorplan'
        AND pv.entity_meta->>'project_id' IS NOT NULL
        AND pv.created_at >= c.since
      GROUP BY (pv.entity_meta->>'project_id')::int
    ),

    -- ── Search clicks (weight: 3) ─────────────────────────────
    search_clicks AS (
      SELECT
        pv.entity_id,
        count(*) AS cnt,
        sum(
          exp(-3.0 * extract(epoch FROM (now() - pv.created_at)) / (window_days * 86400))
        ) AS weighted
      FROM page_views pv, cutoff c
      WHERE pv.entity_type = 'search'
        AND pv.entity_id IS NOT NULL
        AND pv.created_at >= c.since
      GROUP BY pv.entity_id
    ),

    -- ── Compare additions (weight: 4) ─────────────────────────
    compare_adds AS (
      SELECT
        pv.entity_id,
        count(*) AS cnt,
        sum(
          exp(-3.0 * extract(epoch FROM (now() - pv.created_at)) / (window_days * 86400))
        ) AS weighted
      FROM page_views pv, cutoff c
      WHERE pv.entity_type = 'compare'
        AND pv.entity_id IS NOT NULL
        AND pv.created_at >= c.since
      GROUP BY pv.entity_id
    ),

    -- ── Likes (weight: 5) ─────────────────────────────────────
    recent_likes AS (
      SELECT
        l.entity_id,
        count(*) AS cnt,
        sum(
          exp(-3.0 * extract(epoch FROM (now() - l.created_at)) / (window_days * 86400))
        ) AS weighted
      FROM likes l, cutoff c
      WHERE l.entity_type = 'project'
        AND l.created_at >= c.since
      GROUP BY l.entity_id
    ),

    -- ── Calculator usage (weight: 6) ──────────────────────────
    calculator_uses AS (
      SELECT
        pv.entity_id,
        count(*) AS cnt,
        sum(
          exp(-3.0 * extract(epoch FROM (now() - pv.created_at)) / (window_days * 86400))
        ) AS weighted
      FROM page_views pv, cutoff c
      WHERE pv.entity_type = 'calculator'
        AND pv.entity_id IS NOT NULL
        AND pv.created_at >= c.since
      GROUP BY pv.entity_id
    ),

    -- ── PDF interactions (weight: 7) ──────────────────────────
    pdf_interactions AS (
      SELECT
        pv.entity_id,
        count(*) AS cnt,
        sum(
          exp(-3.0 * extract(epoch FROM (now() - pv.created_at)) / (window_days * 86400))
        ) AS weighted
      FROM page_views pv, cutoff c
      WHERE pv.entity_type = 'pdf'
        AND pv.entity_id IS NOT NULL
        AND pv.created_at >= c.since
      GROUP BY pv.entity_id
    ),

    -- ── Saves/favorites (weight: 8) ───────────────────────────
    recent_saves AS (
      SELECT
        f.project_id AS entity_id,
        count(*) AS cnt,
        sum(
          exp(-3.0 * extract(epoch FROM (now() - f.created_at)) / (window_days * 86400))
        ) AS weighted
      FROM favorites f, cutoff c
      WHERE f.favorite_type = 'project'
        AND f.created_at >= c.since
      GROUP BY f.project_id
    ),

    -- ── Shares (weight: 10) ───────────────────────────────────
    recent_shares AS (
      SELECT
        pv.entity_id,
        count(*) AS cnt,
        sum(
          exp(-3.0 * extract(epoch FROM (now() - pv.created_at)) / (window_days * 86400))
        ) AS weighted
      FROM page_views pv, cutoff c
      WHERE pv.entity_type = 'share'
        AND pv.entity_id IS NOT NULL
        AND pv.created_at >= c.since
      GROUP BY pv.entity_id
    ),

    -- ── Chat engagement (weight: 11) ──────────────────────────
    chat_engagements AS (
      SELECT
        pv.entity_id,
        count(*) AS cnt,
        sum(
          exp(-3.0 * extract(epoch FROM (now() - pv.created_at)) / (window_days * 86400))
        ) AS weighted
      FROM page_views pv, cutoff c
      WHERE pv.entity_type = 'chat'
        AND pv.entity_id IS NOT NULL
        AND pv.created_at >= c.since
      GROUP BY pv.entity_id
    ),

    -- ── Contact requests (weight: 12) ─────────────────────────
    recent_contacts AS (
      SELECT
        pv.entity_id,
        count(*) AS cnt,
        sum(
          exp(-3.0 * extract(epoch FROM (now() - pv.created_at)) / (window_days * 86400))
        ) AS weighted
      FROM page_views pv, cutoff c
      WHERE pv.entity_type = 'contact_request'
        AND pv.entity_id IS NOT NULL
        AND pv.created_at >= c.since
      GROUP BY pv.entity_id
    ),

    -- ── Appointments (weight: 15) ─────────────────────────────
    recent_appointments AS (
      SELECT
        a.project_id AS entity_id,
        count(*) AS cnt,
        sum(
          exp(-3.0 * extract(epoch FROM (now() - a.created_at)) / (window_days * 86400))
        ) AS weighted
      FROM appointments a, cutoff c
      WHERE a.project_id IS NOT NULL
        AND a.created_at >= c.since
      GROUP BY a.project_id
    ),

    -- ── Combine all signals ───────────────────────────────────
    combined AS (
      SELECT
        v.entity_id,
        v.entity_name,
        coalesce(v.weighted * 1, 0)
          + coalesce(fv.weighted * 2, 0)
          + coalesce(sc.weighted * 3, 0)
          + coalesce(ca.weighted * 4, 0)
          + coalesce(rl.weighted * 5, 0)
          + coalesce(cu.weighted * 6, 0)
          + coalesce(pd.weighted * 7, 0)
          + coalesce(rs.weighted * 8, 0)
          + coalesce(sh.weighted * 10, 0)
          + coalesce(ce.weighted * 11, 0)
          + coalesce(rc.weighted * 12, 0)
          + coalesce(ra.weighted * 15, 0)
        AS score,
        v.cnt AS view_count,
        coalesce(rl.cnt, 0) AS like_count,
        coalesce(rs.cnt, 0) AS save_count,
        coalesce(sh.cnt, 0) AS share_count,
        coalesce(rc.cnt, 0) AS contact_count,
        coalesce(ra.cnt, 0) AS appointment_count,
        coalesce(sc.cnt, 0) AS search_count,
        coalesce(ca.cnt, 0) AS compare_count,
        coalesce(cu.cnt, 0) AS calculator_count,
        coalesce(pd.cnt, 0) AS pdf_count,
        coalesce(ce.cnt, 0) AS chat_count
      FROM views v
      LEFT JOIN floorplan_views fv ON fv.entity_id = v.entity_id
      LEFT JOIN search_clicks sc ON sc.entity_id = v.entity_id
      LEFT JOIN compare_adds ca ON ca.entity_id = v.entity_id
      LEFT JOIN recent_likes rl ON rl.entity_id = v.entity_id
      LEFT JOIN calculator_uses cu ON cu.entity_id = v.entity_id
      LEFT JOIN pdf_interactions pd ON pd.entity_id = v.entity_id
      LEFT JOIN recent_saves rs ON rs.entity_id = v.entity_id
      LEFT JOIN recent_shares sh ON sh.entity_id = v.entity_id
      LEFT JOIN chat_engagements ce ON ce.entity_id = v.entity_id
      LEFT JOIN recent_contacts rc ON rc.entity_id = v.entity_id
      LEFT JOIN recent_appointments ra ON ra.entity_id = v.entity_id
    )

  SELECT
    combined.entity_id,
    combined.entity_name,
    round(combined.score, 2) AS score,
    combined.view_count,
    combined.like_count,
    combined.save_count,
    combined.share_count,
    combined.contact_count,
    combined.appointment_count,
    combined.search_count,
    combined.compare_count,
    combined.calculator_count,
    combined.pdf_count,
    combined.chat_count
  FROM combined
  WHERE combined.score > 0
  ORDER BY combined.score DESC
  LIMIT result_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

GRANT EXECUTE ON FUNCTION public.get_trending_projects(int, int) TO anon, authenticated;

-- ── 4. Recreate get_lead_scores with all 12 signals ──────────
DROP FUNCTION IF EXISTS public.get_lead_scores(int, int);

CREATE OR REPLACE FUNCTION public.get_lead_scores(
  result_limit int default 50,
  window_days int default 30
)
RETURNS TABLE (
  identifier text,
  user_id uuid,
  email text,
  display_name text,
  phone text,
  score numeric,
  view_count bigint,
  floorplan_view_count bigint,
  like_count bigint,
  save_count bigint,
  share_count bigint,
  contact_count bigint,
  appointment_count bigint,
  search_count bigint,
  compare_count bigint,
  calculator_count bigint,
  pdf_count bigint,
  chat_count bigint,
  last_active timestamptz
) AS $$
BEGIN
  RETURN QUERY
  WITH
    cutoff AS (
      SELECT now() - (window_days || ' days')::interval AS since
    ),

    -- ── Page views — project (weight: 1, dwell-weighted) ──────
    pv_project AS (
      SELECT
        coalesce(pv.user_id::text, pv.visitor_id) AS ident,
        pv.user_id AS uid,
        pv.user_email,
        count(*) AS cnt,
        sum(
          exp(-3.0 * extract(epoch FROM (now() - pv.created_at)) / (window_days * 86400))
          * dwell_multiplier(pv.dwell_seconds)
        ) AS weighted,
        max(pv.created_at) AS latest
      FROM page_views pv, cutoff c
      WHERE pv.entity_type = 'project'
        AND pv.created_at >= c.since
      GROUP BY coalesce(pv.user_id::text, pv.visitor_id), pv.user_id, pv.user_email
    ),

    -- ── Page views — floorplan (weight: 2, dwell-weighted) ────
    pv_floorplan AS (
      SELECT
        coalesce(pv.user_id::text, pv.visitor_id) AS ident,
        pv.user_id AS uid,
        pv.user_email,
        count(*) AS cnt,
        sum(
          exp(-3.0 * extract(epoch FROM (now() - pv.created_at)) / (window_days * 86400))
          * dwell_multiplier(pv.dwell_seconds)
        ) AS weighted,
        max(pv.created_at) AS latest
      FROM page_views pv, cutoff c
      WHERE pv.entity_type = 'floorplan'
        AND pv.created_at >= c.since
      GROUP BY coalesce(pv.user_id::text, pv.visitor_id), pv.user_id, pv.user_email
    ),

    -- ── Search clicks (weight: 3) ─────────────────────────────
    pv_search AS (
      SELECT
        coalesce(pv.user_id::text, pv.visitor_id) AS ident,
        pv.user_id AS uid,
        pv.user_email,
        count(*) AS cnt,
        sum(
          exp(-3.0 * extract(epoch FROM (now() - pv.created_at)) / (window_days * 86400))
        ) AS weighted,
        max(pv.created_at) AS latest
      FROM page_views pv, cutoff c
      WHERE pv.entity_type = 'search'
        AND pv.created_at >= c.since
      GROUP BY coalesce(pv.user_id::text, pv.visitor_id), pv.user_id, pv.user_email
    ),

    -- ── Compare additions (weight: 4) ─────────────────────────
    pv_compare AS (
      SELECT
        coalesce(pv.user_id::text, pv.visitor_id) AS ident,
        pv.user_id AS uid,
        pv.user_email,
        count(*) AS cnt,
        sum(
          exp(-3.0 * extract(epoch FROM (now() - pv.created_at)) / (window_days * 86400))
        ) AS weighted,
        max(pv.created_at) AS latest
      FROM page_views pv, cutoff c
      WHERE pv.entity_type = 'compare'
        AND pv.created_at >= c.since
      GROUP BY coalesce(pv.user_id::text, pv.visitor_id), pv.user_id, pv.user_email
    ),

    -- ── Likes (weight: 5) ─────────────────────────────────────
    user_likes AS (
      SELECT
        l.user_id::text AS ident,
        l.user_id AS uid,
        count(*) AS cnt,
        sum(
          exp(-3.0 * extract(epoch FROM (now() - l.created_at)) / (window_days * 86400))
        ) AS weighted,
        max(l.created_at) AS latest
      FROM likes l, cutoff c
      WHERE l.created_at >= c.since
      GROUP BY l.user_id
    ),

    -- ── Calculator usage (weight: 6) ──────────────────────────
    pv_calculator AS (
      SELECT
        coalesce(pv.user_id::text, pv.visitor_id) AS ident,
        pv.user_id AS uid,
        pv.user_email,
        count(*) AS cnt,
        sum(
          exp(-3.0 * extract(epoch FROM (now() - pv.created_at)) / (window_days * 86400))
        ) AS weighted,
        max(pv.created_at) AS latest
      FROM page_views pv, cutoff c
      WHERE pv.entity_type = 'calculator'
        AND pv.created_at >= c.since
      GROUP BY coalesce(pv.user_id::text, pv.visitor_id), pv.user_id, pv.user_email
    ),

    -- ── PDF interactions (weight: 7) ──────────────────────────
    pv_pdf AS (
      SELECT
        coalesce(pv.user_id::text, pv.visitor_id) AS ident,
        pv.user_id AS uid,
        pv.user_email,
        count(*) AS cnt,
        sum(
          exp(-3.0 * extract(epoch FROM (now() - pv.created_at)) / (window_days * 86400))
        ) AS weighted,
        max(pv.created_at) AS latest
      FROM page_views pv, cutoff c
      WHERE pv.entity_type = 'pdf'
        AND pv.created_at >= c.since
      GROUP BY coalesce(pv.user_id::text, pv.visitor_id), pv.user_id, pv.user_email
    ),

    -- ── Favorites (weight: 8) ─────────────────────────────────
    user_saves AS (
      SELECT
        f.user_id::text AS ident,
        f.user_id AS uid,
        count(*) AS cnt,
        sum(
          exp(-3.0 * extract(epoch FROM (now() - f.created_at)) / (window_days * 86400))
        ) AS weighted,
        max(f.created_at) AS latest
      FROM favorites f, cutoff c
      WHERE f.created_at >= c.since
      GROUP BY f.user_id
    ),

    -- ── Shares (weight: 10) ───────────────────────────────────
    pv_shares AS (
      SELECT
        coalesce(pv.user_id::text, pv.visitor_id) AS ident,
        pv.user_id AS uid,
        pv.user_email,
        count(*) AS cnt,
        sum(
          exp(-3.0 * extract(epoch FROM (now() - pv.created_at)) / (window_days * 86400))
        ) AS weighted,
        max(pv.created_at) AS latest
      FROM page_views pv, cutoff c
      WHERE pv.entity_type = 'share'
        AND pv.created_at >= c.since
      GROUP BY coalesce(pv.user_id::text, pv.visitor_id), pv.user_id, pv.user_email
    ),

    -- ── Chat engagement (weight: 11) ──────────────────────────
    pv_chat AS (
      SELECT
        coalesce(pv.user_id::text, pv.visitor_id) AS ident,
        pv.user_id AS uid,
        pv.user_email,
        count(*) AS cnt,
        sum(
          exp(-3.0 * extract(epoch FROM (now() - pv.created_at)) / (window_days * 86400))
        ) AS weighted,
        max(pv.created_at) AS latest
      FROM page_views pv, cutoff c
      WHERE pv.entity_type = 'chat'
        AND pv.created_at >= c.since
      GROUP BY coalesce(pv.user_id::text, pv.visitor_id), pv.user_id, pv.user_email
    ),

    -- ── Contact requests (weight: 12) ─────────────────────────
    pv_contacts AS (
      SELECT
        coalesce(pv.user_id::text, pv.visitor_id) AS ident,
        pv.user_id AS uid,
        pv.user_email,
        count(*) AS cnt,
        sum(
          exp(-3.0 * extract(epoch FROM (now() - pv.created_at)) / (window_days * 86400))
        ) AS weighted,
        max(pv.created_at) AS latest
      FROM page_views pv, cutoff c
      WHERE pv.entity_type = 'contact_request'
        AND pv.created_at >= c.since
      GROUP BY coalesce(pv.user_id::text, pv.visitor_id), pv.user_id, pv.user_email
    ),

    -- ── Appointments (weight: 15) ─────────────────────────────
    user_appointments AS (
      SELECT
        coalesce(a.user_id::text, a.visitor_id) AS ident,
        a.user_id AS uid,
        a.email AS appt_email,
        a.name AS appt_name,
        a.phone AS appt_phone,
        count(*) AS cnt,
        sum(
          exp(-3.0 * extract(epoch FROM (now() - a.created_at)) / (window_days * 86400))
        ) AS weighted,
        max(a.created_at) AS latest
      FROM appointments a, cutoff c
      WHERE a.created_at >= c.since
      GROUP BY coalesce(a.user_id::text, a.visitor_id), a.user_id, a.email, a.name, a.phone
    ),

    -- ── Collect all identifiers ───────────────────────────────
    all_idents AS (
      SELECT ident FROM pv_project
      UNION SELECT ident FROM pv_floorplan
      UNION SELECT ident FROM pv_search
      UNION SELECT ident FROM pv_compare
      UNION SELECT ident FROM pv_calculator
      UNION SELECT ident FROM pv_pdf
      UNION SELECT ident FROM pv_shares
      UNION SELECT ident FROM pv_chat
      UNION SELECT ident FROM pv_contacts
      UNION SELECT ident FROM user_likes
      UNION SELECT ident FROM user_saves
      UNION SELECT ident FROM user_appointments
    ),

    -- ── Combine all signals ───────────────────────────────────
    combined AS (
      SELECT
        ai.ident,
        coalesce(pp.uid, pf.uid, pse.uid, pco.uid, pca.uid, ppd.uid, ps.uid, pch.uid, pc.uid, ul.uid, us.uid, ua.uid) AS uid,
        coalesce(pp.user_email, pf.user_email, pse.user_email, pco.user_email, pca.user_email, ppd.user_email, ps.user_email, pch.user_email, pc.user_email, ua.appt_email) AS email,
        ua.appt_name AS display_name,
        ua.appt_phone AS phone,
        -- Weighted score
        coalesce(pp.weighted * 1, 0)
          + coalesce(pf.weighted * 2, 0)
          + coalesce(pse.weighted * 3, 0)
          + coalesce(pco.weighted * 4, 0)
          + coalesce(ul.weighted * 5, 0)
          + coalesce(pca.weighted * 6, 0)
          + coalesce(ppd.weighted * 7, 0)
          + coalesce(us.weighted * 8, 0)
          + coalesce(ps.weighted * 10, 0)
          + coalesce(pch.weighted * 11, 0)
          + coalesce(pc.weighted * 12, 0)
          + coalesce(ua.weighted * 15, 0)
        AS score,
        -- Raw counts
        coalesce(pp.cnt, 0) AS view_count,
        coalesce(pf.cnt, 0) AS floorplan_view_count,
        coalesce(ul.cnt, 0) AS like_count,
        coalesce(us.cnt, 0) AS save_count,
        coalesce(ps.cnt, 0) AS share_count,
        coalesce(pc.cnt, 0) AS contact_count,
        coalesce(ua.cnt, 0) AS appointment_count,
        coalesce(pse.cnt, 0) AS search_count,
        coalesce(pco.cnt, 0) AS compare_count,
        coalesce(pca.cnt, 0) AS calculator_count,
        coalesce(ppd.cnt, 0) AS pdf_count,
        coalesce(pch.cnt, 0) AS chat_count,
        greatest(
          pp.latest, pf.latest, pse.latest, pco.latest, pca.latest, ppd.latest,
          ps.latest, pch.latest, pc.latest, ul.latest, us.latest, ua.latest
        ) AS last_active
      FROM all_idents ai
      LEFT JOIN pv_project pp ON pp.ident = ai.ident
      LEFT JOIN pv_floorplan pf ON pf.ident = ai.ident
      LEFT JOIN pv_search pse ON pse.ident = ai.ident
      LEFT JOIN pv_compare pco ON pco.ident = ai.ident
      LEFT JOIN user_likes ul ON ul.ident = ai.ident
      LEFT JOIN pv_calculator pca ON pca.ident = ai.ident
      LEFT JOIN pv_pdf ppd ON ppd.ident = ai.ident
      LEFT JOIN user_saves us ON us.ident = ai.ident
      LEFT JOIN pv_shares ps ON ps.ident = ai.ident
      LEFT JOIN pv_chat pch ON pch.ident = ai.ident
      LEFT JOIN pv_contacts pc ON pc.ident = ai.ident
      LEFT JOIN user_appointments ua ON ua.ident = ai.ident
    )

  SELECT
    combined.ident AS identifier,
    combined.uid AS user_id,
    combined.email,
    combined.display_name,
    combined.phone,
    round(combined.score, 2) AS score,
    combined.view_count,
    combined.floorplan_view_count,
    combined.like_count,
    combined.save_count,
    combined.share_count,
    combined.contact_count,
    combined.appointment_count,
    combined.search_count,
    combined.compare_count,
    combined.calculator_count,
    combined.pdf_count,
    combined.chat_count,
    combined.last_active
  FROM combined
  WHERE combined.score > 0
  ORDER BY combined.score DESC
  LIMIT result_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

GRANT EXECUTE ON FUNCTION public.get_lead_scores(int, int) TO authenticated;
