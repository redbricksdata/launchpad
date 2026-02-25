-- ============================================================
-- CondoLand — Lead Scoring Function
-- ============================================================
-- Computes a weighted engagement score per visitor/user.
-- Pattern mirrors get_trending_projects() but aggregates by
-- person (visitor_id / user_id) instead of by project.
--
-- Signals & weights:
--   Page view:        1    (browsing)
--   Floorplan view:   2    (deeper interest)
--   Like:             5    (explicit signal)
--   Favorite/save:    8    (strong intent)
--   Share:           10    (advocacy)
--   Contact request: 12    (active lead)
--   Appointment:     15    (highest intent)
--
-- Exponential decay: exp(-3.0 * age_seconds / (window_days * 86400))
-- ============================================================

create or replace function public.get_lead_scores(
  result_limit int default 50,
  window_days int default 30
)
returns table (
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
  last_active timestamptz
) as $$
begin
  return query
  with
    cutoff as (
      select now() - (window_days || ' days')::interval as since
    ),

    -- ── Page views — project (weight: 1) ────────────────────
    pv_project as (
      select
        coalesce(pv.user_id::text, pv.visitor_id) as ident,
        pv.user_id as uid,
        pv.user_email,
        count(*) as cnt,
        sum(
          exp(-3.0 * extract(epoch from (now() - pv.created_at)) / (window_days * 86400))
        ) as weighted,
        max(pv.created_at) as latest
      from page_views pv, cutoff c
      where pv.entity_type = 'project'
        and pv.created_at >= c.since
      group by coalesce(pv.user_id::text, pv.visitor_id), pv.user_id, pv.user_email
    ),

    -- ── Page views — floorplan (weight: 2) ──────────────────
    pv_floorplan as (
      select
        coalesce(pv.user_id::text, pv.visitor_id) as ident,
        pv.user_id as uid,
        pv.user_email,
        count(*) as cnt,
        sum(
          exp(-3.0 * extract(epoch from (now() - pv.created_at)) / (window_days * 86400))
        ) as weighted,
        max(pv.created_at) as latest
      from page_views pv, cutoff c
      where pv.entity_type = 'floorplan'
        and pv.created_at >= c.since
      group by coalesce(pv.user_id::text, pv.visitor_id), pv.user_id, pv.user_email
    ),

    -- ── Shares (weight: 10) ─────────────────────────────────
    pv_shares as (
      select
        coalesce(pv.user_id::text, pv.visitor_id) as ident,
        pv.user_id as uid,
        pv.user_email,
        count(*) as cnt,
        sum(
          exp(-3.0 * extract(epoch from (now() - pv.created_at)) / (window_days * 86400))
        ) as weighted,
        max(pv.created_at) as latest
      from page_views pv, cutoff c
      where pv.entity_type = 'share'
        and pv.created_at >= c.since
      group by coalesce(pv.user_id::text, pv.visitor_id), pv.user_id, pv.user_email
    ),

    -- ── Contact requests (weight: 12) ───────────────────────
    pv_contacts as (
      select
        coalesce(pv.user_id::text, pv.visitor_id) as ident,
        pv.user_id as uid,
        pv.user_email,
        count(*) as cnt,
        sum(
          exp(-3.0 * extract(epoch from (now() - pv.created_at)) / (window_days * 86400))
        ) as weighted,
        max(pv.created_at) as latest
      from page_views pv, cutoff c
      where pv.entity_type = 'contact_request'
        and pv.created_at >= c.since
      group by coalesce(pv.user_id::text, pv.visitor_id), pv.user_id, pv.user_email
    ),

    -- ── Likes (weight: 5) ───────────────────────────────────
    user_likes as (
      select
        l.user_id::text as ident,
        l.user_id as uid,
        count(*) as cnt,
        sum(
          exp(-3.0 * extract(epoch from (now() - l.created_at)) / (window_days * 86400))
        ) as weighted,
        max(l.created_at) as latest
      from likes l, cutoff c
      where l.created_at >= c.since
      group by l.user_id
    ),

    -- ── Favorites (weight: 8) ───────────────────────────────
    user_saves as (
      select
        f.user_id::text as ident,
        f.user_id as uid,
        count(*) as cnt,
        sum(
          exp(-3.0 * extract(epoch from (now() - f.created_at)) / (window_days * 86400))
        ) as weighted,
        max(f.created_at) as latest
      from favorites f, cutoff c
      where f.created_at >= c.since
      group by f.user_id
    ),

    -- ── Appointments (weight: 15) ───────────────────────────
    user_appointments as (
      select
        coalesce(a.user_id::text, a.visitor_id) as ident,
        a.user_id as uid,
        a.email as appt_email,
        a.name as appt_name,
        a.phone as appt_phone,
        count(*) as cnt,
        sum(
          exp(-3.0 * extract(epoch from (now() - a.created_at)) / (window_days * 86400))
        ) as weighted,
        max(a.created_at) as latest
      from appointments a, cutoff c
      where a.created_at >= c.since
      group by coalesce(a.user_id::text, a.visitor_id), a.user_id, a.email, a.name, a.phone
    ),

    -- ── Collect all identifiers ─────────────────────────────
    all_idents as (
      select ident from pv_project
      union select ident from pv_floorplan
      union select ident from pv_shares
      union select ident from pv_contacts
      union select ident from user_likes
      union select ident from user_saves
      union select ident from user_appointments
    ),

    -- ── Combine all signals ─────────────────────────────────
    combined as (
      select
        ai.ident,
        coalesce(pp.uid, pf.uid, ps.uid, pc.uid, ul.uid, us.uid, ua.uid) as uid,
        coalesce(pp.user_email, pf.user_email, ps.user_email, pc.user_email, ua.appt_email) as email,
        ua.appt_name as display_name,
        ua.appt_phone as phone,
        -- Weighted score
        coalesce(pp.weighted * 1, 0)
          + coalesce(pf.weighted * 2, 0)
          + coalesce(ul.weighted * 5, 0)
          + coalesce(us.weighted * 8, 0)
          + coalesce(ps.weighted * 10, 0)
          + coalesce(pc.weighted * 12, 0)
          + coalesce(ua.weighted * 15, 0)
        as score,
        -- Raw counts
        coalesce(pp.cnt, 0) as view_count,
        coalesce(pf.cnt, 0) as floorplan_view_count,
        coalesce(ul.cnt, 0) as like_count,
        coalesce(us.cnt, 0) as save_count,
        coalesce(ps.cnt, 0) as share_count,
        coalesce(pc.cnt, 0) as contact_count,
        coalesce(ua.cnt, 0) as appointment_count,
        greatest(
          pp.latest, pf.latest, ps.latest, pc.latest,
          ul.latest, us.latest, ua.latest
        ) as last_active
      from all_idents ai
      left join pv_project pp on pp.ident = ai.ident
      left join pv_floorplan pf on pf.ident = ai.ident
      left join pv_shares ps on ps.ident = ai.ident
      left join pv_contacts pc on pc.ident = ai.ident
      left join user_likes ul on ul.ident = ai.ident
      left join user_saves us on us.ident = ai.ident
      left join user_appointments ua on ua.ident = ai.ident
    )

  select
    combined.ident as identifier,
    combined.uid as user_id,
    combined.email,
    combined.display_name,
    combined.phone,
    round(combined.score, 2) as score,
    combined.view_count,
    combined.floorplan_view_count,
    combined.like_count,
    combined.save_count,
    combined.share_count,
    combined.contact_count,
    combined.appointment_count,
    combined.last_active
  from combined
  where combined.score > 0
  order by combined.score desc
  limit result_limit;
end;
$$ language plpgsql security definer stable;

-- Grant access (admin-only via RLS on calling context, but function is stable/read-only)
grant execute on function public.get_lead_scores(int, int) to authenticated;
