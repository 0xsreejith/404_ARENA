-- Tests for Epic 1: Auth & User Context (me() RPC, branding columns, register_device)
-- Uses pgTAP harness matching docs/DECISIONS.md D35.

begin;
select plan(5);

-- 1. Verify branding columns exist on arena_settings
select has_column('public', 'arena_settings', 'brand_name', 'arena_settings has brand_name');
select has_column('public', 'arena_settings', 'primary_color', 'arena_settings has primary_color');

-- 2. Verify me() RPC function exists
select has_function('public', 'me', array[]::text[], 'public.me() RPC exists');

-- 3. Verify register_device() RPC function exists
select has_function('public', 'register_device', array['uuid', 'uuid', 'text', 'text', 'text'], 'public.register_device() RPC exists');

-- 4. Test unauthenticated call to me() fails gracefully
prepare me_unauth as select public.me();
select throws_ok('me_unauth', 'insufficient_privilege: not authenticated', 'Unauthenticated call to me() throws privilege error');

select * from finish();
rollback;
