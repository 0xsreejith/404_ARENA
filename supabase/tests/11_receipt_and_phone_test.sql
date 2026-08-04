-- M1 — receipt numbering and phone normalisation.
--
-- Both are jurisdiction policy expressed entirely as arena configuration. The
-- assertions below change what they assert by changing rows, never code — which
-- is exactly the property D31 and D36 require.
--
-- Covers SECURITY.md §15 assertions 19 and 20, against DATABASE.md §16.6/§16.7.

begin;
set local search_path to extensions, public, pg_catalog;

\ir fixtures/two_tenants.psql

select plan(12);

-- §16.1 fixture arena configuration. Applied to arena A as data.
update public.arena_settings
   set receipt_prefix = 'FIX/',
       receipt_series_mode = 'financial_yearly',
       receipt_financial_year_start_month = 4,
       receipt_number_format = '{prefix}{series}/{sequence}',
       receipt_number_padding = 6
 where arena_id = :'arena_a';

-- ── §16.6 series derivation ──────────────────────────────────────────────────

select results_eq(
  format(
    $$ select app.receipt_series(%L, d)
         from (values (date '2026-07-30'), (date '2027-03-31'), (date '2027-04-01')) v(d)
        order by d $$,
    :'arena_a'
  ),
  $$ values ('2026-27'), ('2026-27'), ('2027-28') $$,
  'financial_yearly with an April start puts 2026-07-30 and 2027-03-31 in the same '
  'series and starts a new one on 2027-04-01 (§16.6)'
);

select is(
  (select formatted_number from app.next_receipt_number(:'arena_a'::uuid, date '2026-07-30')),
  'FIX/2026-27/000001',
  'the first number of a series renders from the tenant''s template (§16.6)'
);

select is(
  (select sequence_number from app.next_receipt_number(:'arena_a'::uuid, date '2027-03-31')),
  2::bigint,
  'a later date inside the same financial year continues the same counter'
);

select is(
  (select formatted_number from app.next_receipt_number(:'arena_a'::uuid, date '2027-04-01')),
  'FIX/2027-28/000001',
  'the new financial year restarts at 1 with no migration (D13, D31)'
);

-- The same order under a different configuration renders differently, which is
-- the whole point: numbering policy is data.
update public.arena_settings
   set receipt_series_mode = 'fixed',
       receipt_fixed_series = '',
       receipt_number_format = '{prefix}{sequence}'
 where arena_id = :'arena_a';

select is(
  (select formatted_number from app.next_receipt_number(:'arena_a'::uuid, date '2026-07-30')),
  'FIX/000001',
  'switching to fixed mode with an empty series renders FIX/000001 (§16.6)'
);

update public.arena_settings set receipt_series_mode = 'monthly' where arena_id = :'arena_a';
select is(
  app.receipt_series(:'arena_a'::uuid, date '2026-07-30'), '2026-07',
  'monthly mode keys the series by YYYY-MM'
);

update public.arena_settings
   set receipt_series_mode = 'financial_yearly', receipt_financial_year_start_month = 1
 where arena_id = :'arena_a';
select is(
  app.receipt_series(:'arena_a'::uuid, date '2026-07-30'), '2026',
  'a financial year starting in month 1 is identical to yearly (DATABASE.md §10)'
);

-- ── §16.7 phone normalisation ────────────────────────────────────────────────
--
-- Arena A's dial code is +1 and arena B's is +49, both fixture values. The same
-- national number therefore normalises differently per tenant, which is the
-- property D36 is about.

select results_eq(
  format(
    $$ select app.normalise_phone(%L, v.raw)
         from (values (1, '5551234567'), (2, '05551234567'), (3, '+1 555 123 4567'),
                      (4, '+442071838750')) v(n, raw)
        order by v.n $$,
    :'arena_a'
  ),
  $$ values ('+15551234567'), ('+15551234567'), ('+15551234567'), ('+442071838750') $$,
  'a bare national number, a trunk-prefixed one and an already-international one '
  'all reach the same canonical E.164; another country is accepted as given (§16.7)'
);

select throws_like(
  format($$ select app.normalise_phone(%L, '12345') $$, :'arena_a'),
  'validation_failed:%',
  'input that cannot be a valid number is rejected with validation_failed (§16.7)'
);

select throws_like(
  format($$ select app.normalise_phone(%L, '') $$, :'arena_a'),
  'validation_failed:%',
  'an empty phone number is rejected'
);

select is(
  app.normalise_phone(:'arena_b'::uuid, '5551234567'),
  '+495551234567',
  'the dial code is arena configuration, so the same digits normalise per tenant (D36)'
);

-- ── Two spellings of one number cannot both be stored (assertion 20) ─────────

insert into public.members (id, arena_id, full_name, phone, created_by_user_id)
values ('a0000000-0000-4000-8000-0000000000f5', :'arena_a', 'Canonical',
        app.normalise_phone(:'arena_a', '5551234567'), :'user_a_owner');

select throws_ok(
  format(
    $$ insert into public.members (id, arena_id, full_name, phone, created_by_user_id)
       values (gen_random_uuid(), %L, 'Duplicate', app.normalise_phone(%L, '05551234567'), %L) $$,
    :'arena_a', :'arena_a', :'user_a_owner'
  ),
  '23505',
  null,
  'normalising server-side is what makes UNIQUE (arena_id, phone) mean anything: '
  '5551234567 and 05551234567 cannot both exist (D36, assertion 20)'
);

select * from finish();
rollback;
