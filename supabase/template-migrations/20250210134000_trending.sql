-- ============================================================
--  010 — Trending scores (computed from engagement signals)
-- ============================================================
-- Computes a weighted trending score for projects over the last 30 days.
-- Signals: appointments, shares, saves, contact requests, likes, views.
-- Recency-weighted: events from today count more than events from 29 days ago.

-- ── Trending projects function ──────────────────────────────
-- Returns top N projects by weighted engagement score in the last 30 days.
-- Each signal is weighted and decayed by age (exponential decay over 30 days).

create or replace function public.get_trending_projects(
  result_limit int default 10,
  window_days int default 30
)
returns table (
  entity_id int,
  entity_name text,
  score numeric,
  view_count bigint,
  like_count bigint,
  save_count bigint,
  share_count bigint,
  contact_count bigint,
  appointment_count bigint
) as $$
begin
  return query
  with
    -- Time window
    cutoff as (
      select now() - (window_days || ' days')::interval as since
    ),

    -- ── Page views (weight: 1) ──────────────────────────────
    views as (
      select
        pv.entity_id,
        pv.entity_name,
        count(*) as cnt,
        sum(
          exp(-3.0 * extract(epoch from (now() - pv.created_at)) / (window_days * 86400))
        ) as weighted
      from page_views pv, cutoff c
      where pv.entity_type = 'project'
        and pv.entity_id is not null
        and pv.created_at >= c.since
      group by pv.entity_id, pv.entity_name
    ),

    -- ── Likes (weight: 5) ───────────────────────────────────
    recent_likes as (
      select
        l.entity_id,
        count(*) as cnt,
        sum(
          exp(-3.0 * extract(epoch from (now() - l.created_at)) / (window_days * 86400))
        ) as weighted
      from likes l, cutoff c
      where l.entity_type = 'project'
        and l.created_at >= c.since
      group by l.entity_id
    ),

    -- ── Saves/favorites (weight: 8) ─────────────────────────
    recent_saves as (
      select
        f.project_id as entity_id,
        count(*) as cnt,
        sum(
          exp(-3.0 * extract(epoch from (now() - f.created_at)) / (window_days * 86400))
        ) as weighted
      from favorites f, cutoff c
      where f.favorite_type = 'project'
        and f.created_at >= c.since
      group by f.project_id
    ),

    -- ── Shares (weight: 10) ─────────────────────────────────
    recent_shares as (
      select
        pv.entity_id,
        count(*) as cnt,
        sum(
          exp(-3.0 * extract(epoch from (now() - pv.created_at)) / (window_days * 86400))
        ) as weighted
      from page_views pv, cutoff c
      where pv.entity_type = 'share'
        and pv.entity_id is not null
        and pv.created_at >= c.since
      group by pv.entity_id
    ),

    -- ── Contact requests (weight: 12) ───────────────────────
    recent_contacts as (
      select
        pv.entity_id,
        count(*) as cnt,
        sum(
          exp(-3.0 * extract(epoch from (now() - pv.created_at)) / (window_days * 86400))
        ) as weighted
      from page_views pv, cutoff c
      where pv.entity_type = 'contact_request'
        and pv.entity_id is not null
        and pv.created_at >= c.since
      group by pv.entity_id
    ),

    -- ── Appointments (weight: 15) ───────────────────────────
    recent_appointments as (
      select
        a.project_id as entity_id,
        count(*) as cnt,
        sum(
          exp(-3.0 * extract(epoch from (now() - a.created_at)) / (window_days * 86400))
        ) as weighted
      from appointments a, cutoff c
      where a.project_id is not null
        and a.created_at >= c.since
      group by a.project_id
    ),

    -- ── Floorplan views aggregated to project (weight: 2) ───
    -- Floorplan views indicate deeper engagement with the project
    floorplan_views as (
      select
        (pv.entity_meta->>'project_id')::int as entity_id,
        count(*) as cnt,
        sum(
          exp(-3.0 * extract(epoch from (now() - pv.created_at)) / (window_days * 86400))
        ) as weighted
      from page_views pv, cutoff c
      where pv.entity_type = 'floorplan'
        and pv.entity_meta->>'project_id' is not null
        and pv.created_at >= c.since
      group by (pv.entity_meta->>'project_id')::int
    ),

    -- ── Combine all signals ─────────────────────────────────
    combined as (
      select
        v.entity_id,
        v.entity_name,
        -- Weighted score: each signal * its weight
        coalesce(v.weighted * 1, 0)
          + coalesce(rl.weighted * 5, 0)
          + coalesce(rs.weighted * 8, 0)
          + coalesce(sh.weighted * 10, 0)
          + coalesce(rc.weighted * 12, 0)
          + coalesce(ra.weighted * 15, 0)
          + coalesce(fv.weighted * 2, 0)
        as score,
        v.cnt as view_count,
        coalesce(rl.cnt, 0) as like_count,
        coalesce(rs.cnt, 0) as save_count,
        coalesce(sh.cnt, 0) as share_count,
        coalesce(rc.cnt, 0) as contact_count,
        coalesce(ra.cnt, 0) as appointment_count
      from views v
      left join recent_likes rl on rl.entity_id = v.entity_id
      left join recent_saves rs on rs.entity_id = v.entity_id
      left join recent_shares sh on sh.entity_id = v.entity_id
      left join recent_contacts rc on rc.entity_id = v.entity_id
      left join recent_appointments ra on ra.entity_id = v.entity_id
      left join floorplan_views fv on fv.entity_id = v.entity_id
    )

  select
    combined.entity_id,
    combined.entity_name,
    round(combined.score, 2) as score,
    combined.view_count,
    combined.like_count,
    combined.save_count,
    combined.share_count,
    combined.contact_count,
    combined.appointment_count
  from combined
  where combined.score > 0
  order by combined.score desc
  limit result_limit;
end;
$$ language plpgsql security definer stable;

-- Grant access
grant execute on function public.get_trending_projects(int, int) to anon, authenticated;
