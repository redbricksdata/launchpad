-- Migration 006: Visitor preferences v2 — per-dimension counts for multi-carousel recommendations
-- Replaces the original function with richer data: view counts per city, developer count,
-- bedroom breakdown, and favorited project IDs (for logged-in users).

create or replace function public.get_visitor_preferences(p_visitor_id text)
returns jsonb
language plpgsql
security definer
as $$
declare
  result jsonb;
  v_total_views int;
  v_city_views jsonb;
  v_top_building_type text;
  v_avg_price int;
  v_developer_views jsonb;
  v_bedroom_views jsonb;
  v_recent_ids jsonb;
  v_favorited_ids jsonb;
  v_user_id uuid;
begin
  -- Total project views for this visitor
  select count(*)::int into v_total_views
  from public.page_views
  where visitor_id = p_visitor_id
    and entity_type = 'project';

  -- Early exit if insufficient data
  if v_total_views < 3 then
    return jsonb_build_object('total_views', v_total_views);
  end if;

  -- Cities with view counts (top 3)
  select coalesce(jsonb_agg(row_to_json(sub)), '[]'::jsonb) into v_city_views
  from (
    select entity_meta->>'city' as city, count(*)::int as count
    from public.page_views
    where visitor_id = p_visitor_id
      and entity_type = 'project'
      and entity_meta->>'city' is not null
      and entity_meta->>'city' != ''
    group by entity_meta->>'city'
    order by count(*) desc
    limit 3
  ) sub;

  -- Most viewed building type
  select entity_meta->>'building_type' into v_top_building_type
  from public.page_views
  where visitor_id = p_visitor_id
    and entity_type = 'project'
    and entity_meta->>'building_type' is not null
  group by entity_meta->>'building_type'
  order by count(*) desc
  limit 1;

  -- Average price from viewed projects
  select coalesce(avg(
    case
      when entity_meta->>'price_from' ~ '^\$?[\d,]+\.?\d*$'
      then regexp_replace(entity_meta->>'price_from', '[^0-9.]', '', 'g')::numeric
      else null
    end
  )::int, 0) into v_avg_price
  from public.page_views
  where visitor_id = p_visitor_id
    and entity_type = 'project'
    and entity_meta->>'price_from' is not null;

  -- Top developers with view counts (top 3)
  select coalesce(jsonb_agg(row_to_json(sub)), '[]'::jsonb) into v_developer_views
  from (
    select entity_meta->>'developer' as developer, count(*)::int as count
    from public.page_views
    where visitor_id = p_visitor_id
      and entity_type = 'project'
      and entity_meta->>'developer' is not null
      and entity_meta->>'developer' != ''
    group by entity_meta->>'developer'
    order by count(*) desc
    limit 3
  ) sub;

  -- Bedroom preferences from floorplan views with counts
  select coalesce(jsonb_agg(row_to_json(sub)), '[]'::jsonb) into v_bedroom_views
  from (
    select entity_meta->>'bedrooms' as bedrooms, count(*)::int as count
    from public.page_views
    where visitor_id = p_visitor_id
      and entity_type = 'floorplan'
      and entity_meta->>'bedrooms' is not null
    group by entity_meta->>'bedrooms'
    order by count(*) desc
    limit 3
  ) sub;

  -- Recent project IDs for deduplication (last 20 unique)
  select coalesce(jsonb_agg(eid), '[]'::jsonb) into v_recent_ids
  from (
    select distinct on (entity_id) entity_id as eid
    from public.page_views
    where visitor_id = p_visitor_id
      and entity_type = 'project'
      and entity_id is not null
    order by entity_id, created_at desc
    limit 20
  ) sub;

  -- Favorited project IDs (for logged-in users)
  -- Look up user_id from page_views for this visitor
  select user_id into v_user_id
  from public.page_views
  where visitor_id = p_visitor_id
    and user_id is not null
  limit 1;

  if v_user_id is not null then
    select coalesce(jsonb_agg(project_id), '[]'::jsonb) into v_favorited_ids
    from public.favorites
    where user_id = v_user_id
      and favorite_type = 'project';
  else
    v_favorited_ids := '[]'::jsonb;
  end if;

  result := jsonb_build_object(
    'total_views', v_total_views,
    'city_views', v_city_views,
    'top_building_type', v_top_building_type,
    'avg_price', v_avg_price,
    'developer_views', v_developer_views,
    'bedroom_views', v_bedroom_views,
    'recent_project_ids', v_recent_ids,
    'favorited_project_ids', v_favorited_ids
  );

  return result;
end;
$$;

-- Grant execute to anon and authenticated so the API route can call it
grant execute on function public.get_visitor_preferences(text) to anon, authenticated;
