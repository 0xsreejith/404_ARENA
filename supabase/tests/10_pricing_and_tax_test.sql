-- M1 — the normative pricing, tax and allocation algorithms.
--
-- Every expected value below is copied from DATABASE.md §16. Nothing here is a
-- production rate: §16 is a set of test vectors, and real pricing is tenant
-- configuration entered before M4 acceptance (D33).
--
-- Covers SECURITY.md §15 assertions 16, 17 and 18, and the M1 exit clause that
-- the §16 vectors "produce exactly the documented values".

begin;
set local search_path to extensions, public, pg_catalog;

\ir fixtures/two_tenants.psql

select plan(11);

-- §16.3 fixture plans, as pricing snapshots.
create temporary view plans as
select
  '{"billing_plan":{"type":"open_time","hourly_rate":"120.00"},
    "billing_policy":{"grace_minutes":5,"minimum_billable_minutes":30,
                      "rounding_increment_minutes":15,"rounding_mode":"up"}}'::jsonb as plan_a,
  '{"billing_plan":{"type":"fixed_duration","duration_minutes":60,"fixed_price":"150.00"},
    "billing_policy":{"grace_minutes":5}}'::jsonb as plan_b;

-- ── §16.4 play charge vectors ────────────────────────────────────────────────

select results_eq(
  $$
    select v.name, app.play_charge((select plan_a from pg_temp.plans), v.seconds)
      from (values
        ('A1', 4 * 60), ('A2', 5 * 60), ('A3', 6 * 60),
        ('A4', 67 * 60), ('A5', 120 * 60), ('A6', 121 * 60)
      ) as v(name, seconds)
     order by v.name
  $$,
  $$
    values ('A1', 0.00::numeric), ('A2', 0.00), ('A3', 60.00),
           ('A4', 150.00), ('A5', 240.00), ('A6', 270.00)
  $$,
  'plan A: grace boundary, minimum billable, rounding up, and pause exclusion (§16.4)'
);

select results_eq(
  $$
    select v.name, app.play_charge((select plan_b from pg_temp.plans), v.seconds)
      from (values
        ('B1', 3 * 60), ('B2', 45 * 60), ('B3', 62 * 60),
        ('B4', 66 * 60), ('B5', 125 * 60), ('B6', 126 * 60)
      ) as v(name, seconds)
     order by v.name
  $$,
  $$
    values ('B1', 0.00::numeric), ('B2', 150.00), ('B3', 150.00),
           ('B4', 300.00), ('B5', 300.00), ('B6', 450.00)
  $$,
  'plan B: package blocks, with grace applied to the OVERRUN so B3 is not '
  'double-charged (§16.4, audit §10)'
);

-- ── §16.5 tax and total vectors ──────────────────────────────────────────────
--
-- The two-component split below mirrors the §16.2 fixture rate. Both the names
-- and the percentages are arguments, not constants in any function body (D31).

create temporary view split_rate as
select '[{"name":"CGST","percent":"9.00"},{"name":"SGST","percent":"9.00"}]'::jsonb as components;

create temporary view vectors as
select
  app.compute_order_totals(
    jsonb_build_array(jsonb_build_object(
      'quantity', '1.000', 'unit_price', '150.00',
      'tax', jsonb_build_object('percent', '18.00',
                                'components', (select components from pg_temp.split_rate)))),
    true) as t1,
  app.compute_order_totals(
    jsonb_build_array(jsonb_build_object(
      'quantity', '1.000', 'unit_price', '100.00',
      'tax', jsonb_build_object('percent', '18.00',
                                'components', (select components from pg_temp.split_rate)))),
    true) as t2,
  app.compute_order_totals(
    jsonb_build_array(
      jsonb_build_object('quantity', '1.000', 'unit_price', '150.00',
        'tax', jsonb_build_object('percent', '18.00',
                                  'components', (select components from pg_temp.split_rate))),
      jsonb_build_object('quantity', '1.000', 'unit_price', '100.00',
        'tax', jsonb_build_object('percent', '18.00',
                                  'components', (select components from pg_temp.split_rate)))),
    true, 'percent', 10) as t3,
  app.compute_order_totals(
    jsonb_build_array(jsonb_build_object(
      'quantity', '1.000', 'unit_price', '150.00',
      'tax', jsonb_build_object('percent', '18.00',
                                'components', (select components from pg_temp.split_rate)))),
    false) as t4;

select results_eq(
  $$
    select t1->>'subtotal', t1->>'discount_total', t1->>'total',
           t1#>>'{lines,0,taxable_amount}', t1#>>'{lines,0,tax_amount}',
           t1#>>'{lines,0,tax_rate_snapshot,components,0,amount}',
           t1#>>'{lines,0,tax_rate_snapshot,components,1,amount}'
      from pg_temp.vectors
  $$,
  $$ values ('150.00', '0.00', '150.00', '127.12', '22.88', '11.44', '11.44') $$,
  'T1 — one inclusive line, no discount, clean split (§16.5)'
);

select results_eq(
  $$
    select t2#>>'{lines,0,taxable_amount}', t2#>>'{lines,0,tax_amount}',
           t2#>>'{lines,0,tax_rate_snapshot,components,0,amount}',
           t2#>>'{lines,0,tax_rate_snapshot,components,1,amount}',
           t2->>'total'
      from pg_temp.vectors
  $$,
  $$ values ('84.75', '15.25', '7.63', '7.62', '100.00') $$,
  'T2 — the odd minor unit goes to the lowest sort_order, deterministically (§16.5)'
);

select results_eq(
  $$
    select t3->>'subtotal', t3->>'discount_total', t3->>'tax_total', t3->>'total',
           t3#>>'{lines,0,discount_amount}', t3#>>'{lines,0,taxable_amount}',
           t3#>>'{lines,0,tax_amount}', t3#>>'{lines,0,line_total}',
           t3#>>'{lines,0,tax_rate_snapshot,components,0,amount}',
           t3#>>'{lines,0,tax_rate_snapshot,components,1,amount}',
           t3#>>'{lines,1,discount_amount}', t3#>>'{lines,1,taxable_amount}',
           t3#>>'{lines,1,tax_amount}', t3#>>'{lines,1,line_total}',
           t3#>>'{lines,1,tax_rate_snapshot,components,0,amount}',
           t3#>>'{lines,1,tax_rate_snapshot,components,1,amount}'
      from pg_temp.vectors
  $$,
  $$
    values ('250.00', '25.00', '34.32', '225.00',
            '15.00', '114.41', '20.59', '135.00', '10.30', '10.29',
            '10.00', '76.27',  '13.73', '90.00',  '6.87',  '6.86')
  $$,
  'T3 — two lines, a 10% order discount allocated by line_subtotal (§16.5)'
);

select results_eq(
  $$
    select t4->>'subtotal', t4->>'tax_total', t4->>'total',
           t4#>>'{lines,0,taxable_amount}',
           t4#>>'{lines,0,tax_rate_snapshot,components,0,amount}',
           t4#>>'{lines,0,tax_rate_snapshot,components,1,amount}',
           (t4#>>'{lines,0,tax_rate_snapshot,inclusive}')
      from pg_temp.vectors
  $$,
  $$ values ('150.00', '27.00', '177.00', '150.00', '13.50', '13.50', 'false') $$,
  'T4 — the exclusive branch, proving both modes are supported (§16.5, D32)'
);

-- ── Components sum EXACTLY to the line tax, on every vector ──────────────────

select is_empty(
  $$
    select vector || ' line ' || (line->>'index')
      from pg_temp.vectors v
      cross join lateral (values ('T1', v.t1), ('T2', v.t2), ('T3', v.t3), ('T4', v.t4))
        as r(vector, result)
      cross join lateral jsonb_array_elements(r.result -> 'lines') as line
     where (
             select coalesce(sum((c->>'amount')::numeric), 0)
               from jsonb_array_elements(line #> '{tax_rate_snapshot,components}') c
           ) <> (line->>'tax_amount')::numeric
  $$,
  'component amounts sum exactly to each line''s tax_amount, on every vector (assertion 17)'
);

-- ── tax_rates.percent is the maintained sum of live components (D31) ─────────

select is(
  (select percent from public.tax_rates where id = 'a0000000-0000-4000-8000-000000000004'),
  10.00::numeric,
  'tax_rates.percent equals the sum of its live components after insert (assertion 18)'
);

update public.tax_rate_components set percent = 8.00
 where id = 'a0000000-0000-4000-8000-000000000005';

select is(
  (select percent from public.tax_rates where id = 'a0000000-0000-4000-8000-000000000004'),
  12.00::numeric,
  'editing a component recomputes the rate'
);

update public.tax_rate_components set deleted_at = now()
 where id = 'a0000000-0000-4000-8000-000000000005';

select is(
  (select percent from public.tax_rates where id = 'a0000000-0000-4000-8000-000000000004'),
  4.00::numeric,
  'soft-deleting a component recomputes the rate from the live ones only'
);

select throws_like(
  $$ update public.tax_rate_components set deleted_at = now()
      where id = 'a0000000-0000-4000-8000-000000000006' $$,
  'validation_failed:%',
  'the last live component of a rate cannot be removed — a jurisdiction with no '
  'split configures a single component (assertion 18)'
);

select * from finish();
rollback;
