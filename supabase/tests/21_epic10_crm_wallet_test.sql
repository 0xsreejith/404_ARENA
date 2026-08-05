-- Epic 10 Wave B/C — CRM depth + wallet/loyalty smoke pgTAP.

begin;
set local search_path to extensions, public, pg_catalog;

\ir fixtures/two_tenants.psql

select plan(8);

\set member_crm 'e1b00000-0000-4000-8000-000000000001'
\set plan_gold 'e1b00000-0000-4000-8000-000000000010'

reset role;
select pg_temp.become(:'user_a_owner');
set local role authenticated;

select lives_ok(
  format(
    $$ select public.member_create(
         %L, %L, 'CRM Member', '5550007777', null, null, 'idem-crm-1'
       ) $$,
    :'arena_a', :'member_crm'
  ),
  'Owner can create CRM member'
);

select ok(
  (public.member_get(:'arena_a'::uuid, :'member_crm'::uuid) ? 'stats')
  and (public.member_get(:'arena_a'::uuid, :'member_crm'::uuid) ? 'wallet_balance'),
  'member_get returns stats and wallet_balance'
);

select lives_ok(
  format(
    $$ select public.member_note_add(%L, %L, 'general', 'Prefers PS-02') $$,
    :'arena_a', :'member_crm'
  ),
  'Owner can add a member note'
);

select is(
  jsonb_array_length(public.member_note_list(:'arena_a'::uuid, :'member_crm'::uuid)->'notes'),
  1,
  'Note list returns the added note'
);

select lives_ok(
  format(
    $$ select public.wallet_topup(%L, %L, 100.00, 'opening') $$,
    :'arena_a', :'member_crm'
  ),
  'Wallet topup succeeds'
);

select throws_ok(
  format(
    $$ select public.wallet_debit(%L, %L, 500.00, 'too much') $$,
    :'arena_a', :'member_crm'
  ),
  'P0001',
  'insufficient_funds: wallet balance 100.00',
  'Wallet debit rejects insufficient funds'
);

select lives_ok(
  format(
    $$ select public.membership_plan_upsert(
         %L, %L, 'Gold', 999.00, 30, '{"seats":1}'::jsonb, true
       ) $$,
    :'arena_a', :'plan_gold'
  ),
  'Membership plan upsert succeeds'
);

select lives_ok(
  format(
    $$ select public.membership_subscribe(%L, %L, %L) $$,
    :'arena_a', :'member_crm', :'plan_gold'
  ),
  'Membership subscribe succeeds'
);

select * from finish();
rollback;
