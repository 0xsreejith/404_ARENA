-- Epic 3C — Checkout Integrity pgTAP.
-- Asserts order_preview / settle use M1 algorithms (no hardcoded 1.18 / FIX/).
-- Governed by: DATABASE.md §9–§10 · DECISIONS D01, D11, D13, D31, D32 ·
--              IMPLEMENTATION_PLAN.md Epic 3C
--
-- Client entity ids use hex-only UUIDs (prefix e3…).

begin;
set local search_path to extensions, public, pg_catalog;

\ir fixtures/two_tenants.psql

select plan(22);

\set order_play   'e3000000-0000-4000-8000-000000000001'
\set order_counter 'e3000000-0000-4000-8000-000000000002'
\set pay_1        'e3300000-0000-4000-8000-000000000001'
\set pay_2        'e3300000-0000-4000-8000-000000000002'
\set item_1       'e3400000-0000-4000-8000-000000000001'
\set sess_new     'e3200000-0000-4000-8000-000000000001'

-- Fixture leaves station a…002 with an active session (a…00c). Free it and
-- drive a completed session with a known elapsed window for play-charge math.
reset role;

update public.sessions
   set status = 'completed',
       ended_at = started_at + interval '67 minutes',
       end_reason = 'normal',
       ended_by_user_id = :'user_a_owner'
 where id = 'a0000000-0000-4000-8000-00000000000c'
   and arena_id = :'arena_a';

update public.arena_settings
   set default_play_tax_rate_id = 'a0000000-0000-4000-8000-000000000004',
       default_product_tax_rate_id = 'a0000000-0000-4000-8000-000000000004',
       prices_include_tax = true,
       receipt_prefix = 'TST/',
       receipt_number_format = '{prefix}{series}/{sequence}',
       receipt_number_padding = 6
 where arena_id = :'arena_a';

update public.orders
   set status = 'void', void_reason = 'epic3c test reset'
 where id = 'a0000000-0000-4000-8000-00000000000d'
   and arena_id = :'arena_a';

select pg_temp.become(:'user_a_staff');
set local role authenticated;

-- ── 1–2: open + preview play charge (67m open_time @ 100/h) ──────────────────
-- Snapshot: grace 5, min 30, round 15 up → billable 75 → 100 * 75/60 = 125.00

select lives_ok(
  format(
    $$ select public.checkout_open(%L, %L, 'a0000000-0000-4000-8000-00000000000c') $$,
    :'arena_a', :'order_play'
  ),
  'Staff can open checkout for a completed session'
);

select results_eq(
  format(
    $$ select (public.order_preview(%L, %L)->>'subtotal')::numeric,
              (public.order_preview(%L, %L)->>'total')::numeric $$,
    :'arena_a', :'order_play', :'arena_a', :'order_play'
  ),
  $$ select 125.00::numeric, 125.00::numeric $$,
  'Preview play charge is 125.00 inclusive total (M1 play_charge, no client math)'
);

select results_eq(
  format(
    $$ select (public.order_preview(%L, %L)->>'tax_total')::numeric $$,
    :'arena_a', :'order_play'
  ),
  $$ select 11.36::numeric $$,
  'Preview tax_total uses arena tax rate via compute_order_totals (not 1.18)'
);

-- ── 3–4: discount reason required (owner has discount.apply) ─────────────────

reset role;
select pg_temp.become(:'user_a_owner');
set local role authenticated;

select throws_ok(
  format(
    $$ select public.order_apply_discount(%L, %L, 'flat', 10.00, '') $$,
    :'arena_a', :'order_play'
  ),
  'P0001',
  'validation_failed: discount reason is required',
  'Discount without reason is rejected'
);

select lives_ok(
  format(
    $$ select public.order_apply_discount(%L, %L, 'flat', 25.00, 'Loyalty') $$,
    :'arena_a', :'order_play'
  ),
  'Owner can apply flat discount with reason'
);

select results_eq(
  format(
    $$ select (public.order_preview(%L, %L)->>'discount_total')::numeric,
              (public.order_preview(%L, %L)->>'total')::numeric $$,
    :'arena_a', :'order_play', :'arena_a', :'order_play'
  ),
  $$ select 25.00::numeric, 100.00::numeric $$,
  'Flat 25 off 125 → total 100 (inclusive)'
);

-- ── 5–8: partial then settle; receipt from settings template ─────────────────

select lives_ok(
  format(
    $$ select public.order_settle(%L, %L, %L, 'cash', 40.00, null, 'idem-settle-1') $$,
    :'arena_a', :'order_play', :'pay_1'
  ),
  'Partial cash payment recorded'
);

select results_eq(
  format(
    $$ select paid_total from public.orders where id = %L $$,
    :'order_play'
  ),
  $$ select 40.00::numeric $$,
  'paid_total reflects partial payment'
);

select lives_ok(
  format(
    $$ select public.order_settle(%L, %L, %L, 'upi', 60.00, 'UPI1', 'idem-settle-2') $$,
    :'arena_a', :'order_play', :'pay_2'
  ),
  'Remaining balance settled via UPI'
);

select results_eq(
  format(
    $$ select status, receipt_number like 'TST/%%'
         from public.orders where id = %L $$,
    :'order_play'
  ),
  $$ select 'settled'::text, true $$,
  'Settled receipt uses arena receipt_prefix/format (not hardcoded FIX/)'
);

select results_eq(
  format(
    $$ select (public.order_settle(%L, %L, %L, 'upi', 60.00, 'UPI1', 'idem-settle-2')
         ->>'status') $$,
    :'arena_a', :'order_play', :'pay_2'
  ),
  $$ select 'settled'::text $$,
  'Settle idempotency key replays succeeded response'
);

select throws_ok(
  format(
    $$ select public.order_apply_discount(%L, %L, 'flat', 5.00, 'Extra') $$,
    :'arena_a', :'order_play'
  ),
  'P0001',
  'invalid_state: cannot apply discount to settled order',
  'Settled order rejects discount'
);

-- ── 9–12: counter sale + product + void ──────────────────────────────────────

select lives_ok(
  format(
    $$ select public.checkout_open(%L, %L, null) $$,
    :'arena_a', :'order_counter'
  ),
  'Counter sale order (no session)'
);

select lives_ok(
  format(
    $$ select public.order_add_product(%L, %L, %L,
         'a0000000-0000-4000-8000-000000000009', 2.0) $$,
    :'arena_a', :'order_counter', :'item_1'
  ),
  'Add product line (fixture Product One @ 50.00 × 2)'
);

select results_eq(
  format(
    $$ select (public.order_preview(%L, %L)->>'subtotal')::numeric,
              (public.order_preview(%L, %L)->>'tax_total')::numeric $$,
    :'arena_a', :'order_counter', :'arena_a', :'order_counter'
  ),
  $$ select 100.00::numeric, 9.09::numeric $$,
  'Product preview: subtotal 100, inclusive 10% tax 9.09 via compute_order_totals'
);

select lives_ok(
  format(
    $$ select public.order_void(%L, %L, 'Customer changed mind') $$,
    :'arena_a', :'order_counter'
  ),
  'Void open counter sale with reason'
);

-- ── 13–14: no 1.18 / FIX literals remain in checkout RPC bodies ──────────────

reset role;

select is(
  (select count(*)::int
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'order_preview', 'order_settle', 'checkout_open', 'order_add_product'
      )
      and pg_get_functiondef(p.oid) like '%1.18%'),
  0,
  'Checkout RPCs contain no hardcoded 1.18 tax divisor'
);

select is(
  (select count(*)::int
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'order_settle'
      and pg_get_functiondef(p.oid) like '%FIX/%'),
  0,
  'order_settle contains no hardcoded FIX/ receipt prefix'
);

-- ── 15–16: session_start writes nested billing_plan snapshot ─────────────────

select pg_temp.become(:'user_a_staff');
set local role authenticated;

select lives_ok(
  format(
    $$ select public.session_start(%L, %L,
         'a0000000-0000-4000-8000-000000000002',
         'a0000000-0000-4000-8000-000000000007') $$,
    :'arena_a', :'sess_new'
  ),
  'session_start succeeds on free station'
);

select results_eq(
  format(
    $$ select pricing_snapshot #>> '{billing_plan,type}',
              pricing_snapshot #>> '{billing_plan,hourly_rate}'
         from public.sessions where id = %L $$,
    :'sess_new'
  ),
  $$ select 'open_time'::text, '100.00'::text $$,
  'session_start persists normative billing_plan snapshot (D11)'
);

-- ── 17–18: missing session / voided order product add ────────────────────────

select throws_ok(
  format(
    $$ select public.checkout_open(%L, 'e3000000-0000-4000-8000-000000000099',
         'e3200000-0000-4000-8000-000000009999') $$,
    :'arena_a'
  ),
  'P0001',
  'not_found: session e3200000-0000-4000-8000-000000009999',
  'checkout_open rejects unknown session'
);

select throws_ok(
  format(
    $$ select public.order_add_product(%L, %L,
         'e3400000-0000-4000-8000-000000000099',
         'a0000000-0000-4000-8000-000000000009', 1.0) $$,
    :'arena_a', :'order_counter'
  ),
  'P0001',
  'invalid_state: cannot modify void order',
  'Cannot add product to voided order'
);

select * from finish();
rollback;
