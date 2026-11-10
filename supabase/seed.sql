-- ACME Control — initial demo data.
-- Runs automatically after migrations on `supabase db reset`.
-- Demo user accounts are created separately with `pnpm --dir api seed:users`
-- (which calls acme_reset_demo() again so records are attributed to them).
select public.acme_reset_demo();
