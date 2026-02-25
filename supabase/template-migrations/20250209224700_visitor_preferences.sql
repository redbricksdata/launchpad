-- Migration 005: Visitor preferences function for personalized recommendations
-- Security definer function that aggregates browsing patterns from page_views
-- bypassing RLS safely (returns only aggregated data, not raw rows)

create or replace function public.get_visitor_preferences(p_visitor_id text)
returns jsonb
language plpgsql
security definer
as $$
declare
  result jsonb;
  v_total_views int;
  v_top_cities jsonb;
  v_top_building_type text;
  v_avg_price int;
  v_top_developer text;
  v_top_bedrooms text;
  v_recent_ids jsonb;
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

  -- Top 3 cities by view count
  select coalesce(jsonb_agg(city), '[]'::jsonb) into v_top_cities
  from (
    select entity_meta->>'city' as city
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

  -- Average price from viewed projects (filter non-numeric values)
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

  -- Most viewed developer (if tracked in entity_meta)
  select entity_meta->>'developer' into v_top_developer
  from public.page_views
  where visitor_id = p_visitor_id
    and entity_type = 'project'
    and entity_meta->>'developer' is not null
    and entity_meta->>'developer' != ''
  group by entity_meta->>'developer'
  order by count(*) desc
  limit 1;

  -- Most viewed bedroom count from floorplan views
  select entity_meta->>'bedrooms' into v_top_bedrooms
  from public.page_views
  where visitor_id = p_visitor_id
    and entity_type = 'floorplan'
    and entity_meta->>'bedrooms' is not null
  group by entity_meta->>'bedrooms'
  order by count(*) desc
  limit 1;

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

  result := jsonb_build_object(
    'total_views', v_total_views,
    'top_cities', v_top_cities,
    'top_building_type', v_top_building_type,
    'avg_price', v_avg_price,
    'top_developer', v_top_developer,
    'top_bedrooms', v_top_bedrooms,
    'recent_project_ids', v_recent_ids
  );

  return result;
end;
$$;

-- Grant execute to anon and authenticated so the API route can call it
grant execute on function public.get_visitor_preferences(text) to anon, authenticated;
