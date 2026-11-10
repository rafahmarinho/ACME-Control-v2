-- ACME Control — server-side trend downsampling.
-- Returns at most p_points buckets per tag (bucket average), so trend queries
-- stay below PostgREST's max-rows limit regardless of the time range.

create or replace function public.trend_series(
  p_plant  text,
  p_tags   text[],
  p_from   timestamptz,
  p_to     timestamptz,
  p_points int default 300
)
returns table (tag text, ts timestamptz, value numeric)
language sql
stable
set search_path = public
as $$
  select m.tag,
         date_bin(
           make_interval(secs => greatest(1, extract(epoch from (p_to - p_from)) / greatest(p_points, 10))),
           m.ts,
           p_from
         ) as ts,
         round(avg(m.value), 2) as value
    from public.measurements m
   where m.plant_id = p_plant
     and m.tag = any (p_tags)
     and m.ts between p_from and p_to
   group by 1, 2
   order by 2, 1
$$;

revoke execute on function public.trend_series(text, text[], timestamptz, timestamptz, int) from public, anon;
grant execute on function public.trend_series(text, text[], timestamptz, timestamptz, int) to authenticated;
