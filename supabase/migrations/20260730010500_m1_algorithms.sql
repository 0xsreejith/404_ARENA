-- M1 — normative computations and reconciliation.
--
-- The play-charge, discount-allocation, tax and component-allocation algorithms
-- are normative in DATABASE.md §9 and §10, with worked vectors in §16. They
-- land here, in the internal `app` schema, because the M1 exit criterion is
-- that those vectors "produce exactly the documented values" — which is only
-- verifiable once an implementation exists.
--
-- These are pure functions. They read no table, write no row and know nothing
-- about orders. The M6 RPCs (checkout_open, order_preview, order_settle) feed
-- them rows and persist what comes back; that wiring is M6, not M1.
--
-- No rate, package price, grace period, rounding increment, tax percentage or
-- component name appears in any body below. Every value arrives as an argument
-- from tenant configuration (D33).
--
-- Governing: DATABASE.md §7, §9, §10, §16 · D01, D10, D11, D20, D31, D32.

-- ── Money and percent rendering ──────────────────────────────────────────────
-- All money and percentage values cross a JSON boundary as strings, to avoid
-- float round-tripping (DATABASE.md §9). Consumers parse to numeric or to a
-- minor-unit int.

create function app.money_text(p_amount numeric)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  select p_amount::numeric(12, 2)::text;
$$;

create function app.percent_text(p_percent numeric)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  select p_percent::numeric(5, 2)::text;
$$;

-- ── Largest-remainder allocation ─────────────────────────────────────────────
-- Used twice: to spread an order discount across lines by line_subtotal, and to
-- split a line's tax across its rate's components (DATABASE.md §10).
--
-- The guarantee is that the returned amounts sum EXACTLY to p_total, with any
-- odd minor unit assigned deterministically to the earliest index rather than
-- drifting between components.

create function app.allocate_by_largest_remainder(p_total numeric, p_raw numeric[])
returns numeric[]
language plpgsql
immutable
set search_path = pg_catalog
as $$
declare
  v_count      int;
  v_base       numeric[] := array[]::numeric[];
  v_fraction   numeric[] := array[]::numeric[];
  v_order      int[];
  v_assigned   numeric := 0;
  v_units      int;
  v_index      int;
begin
  v_count := coalesce(array_length(p_raw, 1), 0);
  if v_count = 0 then
    return '{}'::numeric[];
  end if;

  for v_i in 1 .. v_count loop
    v_base[v_i]     := trunc(p_raw[v_i], 2);
    v_fraction[v_i] := p_raw[v_i] - v_base[v_i];
    v_assigned      := v_assigned + v_base[v_i];
  end loop;

  v_units := round((p_total - v_assigned) * 100)::int;

  if v_units > 0 then
    -- Largest remainder first; ties broken by index, which the caller supplies
    -- in sort_order.
    select array_agg(g.i order by v_fraction[g.i] desc, g.i asc)
      into v_order
      from generate_series(1, v_count) as g(i);

    for v_i in 1 .. least(v_units, v_count) loop
      v_index := v_order[v_i];
      v_base[v_index] := v_base[v_index] + 0.01;
    end loop;

    if v_units > v_count then
      v_base[1] := v_base[1] + (v_units - v_count) * 0.01;
    end if;

  elsif v_units < 0 then
    -- Defensive: rounding of the line total can leave the raw shares fractionally
    -- above the total. Remove units from the smallest remainders so the sum is
    -- still exact.
    select array_agg(g.i order by v_fraction[g.i] asc, g.i asc)
      into v_order
      from generate_series(1, v_count) as g(i);

    for v_i in 1 .. least(-v_units, v_count) loop
      v_index := v_order[v_i];
      v_base[v_index] := v_base[v_index] - 0.01;
    end loop;

    if -v_units > v_count then
      v_base[1] := v_base[1] - (-v_units - v_count) * 0.01;
    end if;
  end if;

  return v_base;
end;
$$;

comment on function app.allocate_by_largest_remainder(numeric, numeric[]) is
  'Allocates p_total across the raw shares so the result sums exactly to '
  'p_total (DATABASE.md §10). Ties go to the lowest index — never left to '
  'float between two halves of a split rate (D31).';

-- ── Play charge ──────────────────────────────────────────────────────────────

create function app.round_minutes(p_minutes int, p_increment int, p_mode text)
returns int
language plpgsql
immutable
set search_path = pg_catalog
as $$
declare
  v_increment int := greatest(coalesce(p_increment, 1), 1);
  v_blocks    numeric;
begin
  v_blocks := p_minutes::numeric / v_increment;

  if p_mode = 'up' then
    return (ceil(v_blocks) * v_increment)::int;
  elsif p_mode = 'down' then
    return (floor(v_blocks) * v_increment)::int;
  elsif p_mode = 'nearest' then
    return (round(v_blocks) * v_increment)::int;
  end if;

  raise exception 'validation_failed: unknown rounding_mode %', p_mode
    using errcode = 'P0001';
end;
$$;

create function app.play_charge(p_pricing_snapshot jsonb, p_elapsed_seconds bigint)
returns numeric
language plpgsql
immutable
set search_path = pg_catalog, app
as $$
declare
  v_type             text;
  v_grace            int;
  v_elapsed_minutes  int;
  v_billable_minutes int;
  v_duration         int;
  v_overrun          int;
  v_blocks           int;
  v_amount           numeric;
begin
  v_type  := p_pricing_snapshot #>> '{billing_plan,type}';
  v_grace := coalesce((p_pricing_snapshot #>> '{billing_policy,grace_minutes}')::int, 0);

  -- 1, 2: paused time is already excluded by the caller.
  v_elapsed_minutes := ceil(greatest(coalesce(p_elapsed_seconds, 0), 0)::numeric / 60)::int;

  -- 3: the grace boundary is inclusive, and covers "started and immediately
  -- stopped" for both plan types.
  if v_elapsed_minutes <= v_grace then
    return 0.00::numeric;
  end if;

  if v_type = 'open_time' then
    -- 4: minimum first, then rounding. Both are open_time-only settings.
    v_billable_minutes := greatest(
      v_elapsed_minutes,
      coalesce((p_pricing_snapshot #>> '{billing_policy,minimum_billable_minutes}')::int, 0)
    );
    v_billable_minutes := app.round_minutes(
      v_billable_minutes,
      coalesce((p_pricing_snapshot #>> '{billing_policy,rounding_increment_minutes}')::int, 1),
      coalesce(p_pricing_snapshot #>> '{billing_policy,rounding_mode}', 'up')
    );
    v_amount := (p_pricing_snapshot #>> '{billing_plan,hourly_rate}')::numeric
                  * v_billable_minutes / 60;

  elsif v_type = 'fixed_duration' then
    -- 5: grace forgives the OVERRUN, so a customer two minutes past a package
    -- pays for one package, not two (DATABASE.md §9, audit §10).
    v_duration := (p_pricing_snapshot #>> '{billing_plan,duration_minutes}')::int;
    if v_duration is null or v_duration <= 0 then
      raise exception 'validation_failed: fixed_duration plan has no duration_minutes'
        using errcode = 'P0001';
    end if;
    v_overrun := greatest(0, v_elapsed_minutes - v_duration - v_grace);
    v_blocks  := 1 + ceil(v_overrun::numeric / v_duration)::int;
    v_amount  := (p_pricing_snapshot #>> '{billing_plan,fixed_price}')::numeric * v_blocks;

  else
    raise exception 'validation_failed: unknown billing plan type %', coalesce(v_type, '<null>')
      using errcode = 'P0001';
  end if;

  -- 6: half-up to two decimal places.
  return round(v_amount, 2);
end;
$$;

comment on function app.play_charge(jsonb, bigint) is
  'The normative play-charge algorithm (DATABASE.md §9), computed from the '
  'session''s immutable pricing snapshot only — never from current '
  'configuration (D11). Worked vectors: DATABASE.md §16.4.';

-- ── Order totals, tax and component snapshots ────────────────────────────────

create function app.compute_order_totals(
  p_lines              jsonb,
  p_prices_include_tax boolean,
  p_discount_kind      text default null,
  p_discount_value     numeric default null
)
returns jsonb
language plpgsql
-- STABLE rather than IMMUTABLE: jsonb_build_object is stable, because the type
-- output functions it calls are. The arithmetic itself is pure.
stable
set search_path = pg_catalog, app
as $$
declare
  v_count          int;
  v_component_count int;
  v_line           jsonb;
  v_components     jsonb;
  v_component      jsonb;
  v_subtotals      numeric[] := array[]::numeric[];
  v_raw_shares     numeric[] := array[]::numeric[];
  v_discounts      numeric[] := array[]::numeric[];
  v_component_raw  numeric[];
  v_component_amt  numeric[];
  v_subtotal       numeric := 0;
  v_discount_total numeric := 0;
  v_tax_total      numeric := 0;
  v_net            numeric;
  v_percent        numeric;
  v_taxable        numeric;
  v_tax            numeric;
  v_line_total     numeric;
  v_component_json jsonb;
  v_out_lines      jsonb := '[]'::jsonb;
  v_total          numeric;
begin
  v_count := coalesce(jsonb_array_length(p_lines), 0);

  -- 1, 2
  for v_i in 1 .. v_count loop
    v_line := p_lines -> (v_i - 1);
    v_subtotals[v_i] := round(
      (v_line ->> 'quantity')::numeric * (v_line ->> 'unit_price')::numeric, 2
    );
    v_subtotal := v_subtotal + v_subtotals[v_i];
  end loop;

  -- 3: resolve the order discount
  if p_discount_kind = 'flat' then
    v_discount_total := least(greatest(coalesce(p_discount_value, 0), 0), v_subtotal);
  elsif p_discount_kind = 'percent' then
    v_discount_total := round(v_subtotal * greatest(coalesce(p_discount_value, 0), 0) / 100, 2);
  elsif p_discount_kind is not null then
    raise exception 'validation_failed: unknown discount kind %', p_discount_kind
      using errcode = 'P0001';
  end if;

  -- 4: allocate it across lines proportionally to line_subtotal
  for v_i in 1 .. v_count loop
    v_discounts[v_i] := 0;
  end loop;
  if v_count > 0 and v_subtotal > 0 and v_discount_total > 0 then
    for v_i in 1 .. v_count loop
      v_raw_shares[v_i] := v_discount_total * v_subtotals[v_i] / v_subtotal;
    end loop;
    v_discounts := app.allocate_by_largest_remainder(v_discount_total, v_raw_shares);
  end if;

  -- 5, 6, 7
  for v_i in 1 .. v_count loop
    v_line    := p_lines -> (v_i - 1);
    v_net     := v_subtotals[v_i] - v_discounts[v_i];
    v_percent := coalesce((v_line #>> '{tax,percent}')::numeric, 0);

    if p_prices_include_tax then
      v_taxable    := round(v_net / (1 + v_percent / 100), 2);
      v_tax        := v_net - v_taxable;
      v_line_total := v_net;
    else
      v_taxable    := v_net;
      v_tax        := round(v_net * v_percent / 100, 2);
      v_line_total := v_net + v_tax;
    end if;

    v_components      := coalesce(v_line #> '{tax,components}', '[]'::jsonb);
    v_component_count := jsonb_array_length(v_components);
    v_component_raw   := array[]::numeric[];
    v_component_json  := '[]'::jsonb;

    for v_j in 1 .. v_component_count loop
      v_component_raw[v_j] :=
        v_taxable * (v_components -> (v_j - 1) ->> 'percent')::numeric / 100;
    end loop;

    if v_component_count > 0 then
      v_component_amt := app.allocate_by_largest_remainder(v_tax, v_component_raw);
      for v_j in 1 .. v_component_count loop
        v_component := v_components -> (v_j - 1);
        v_component_json := v_component_json || jsonb_build_object(
          'name',    v_component ->> 'name',
          'percent', app.percent_text((v_component ->> 'percent')::numeric),
          'amount',  app.money_text(v_component_amt[v_j])
        );
      end loop;
    end if;

    v_tax_total := v_tax_total + v_tax;

    v_out_lines := v_out_lines || jsonb_build_object(
      'index',           v_i - 1,
      'line_subtotal',   app.money_text(v_subtotals[v_i]),
      'discount_amount', app.money_text(v_discounts[v_i]),
      'taxable_amount',  app.money_text(v_taxable),
      'tax_amount',      app.money_text(v_tax),
      'line_total',      app.money_text(v_line_total),
      'tax_rate_snapshot', jsonb_build_object(
        'schema_version', 1,
        'rate_id',        v_line #>> '{tax,rate_id}',
        'name',           v_line #>> '{tax,name}',
        'percent',        app.percent_text(v_percent),
        'inclusive',      p_prices_include_tax,
        'taxable_amount', app.money_text(v_taxable),
        'tax_amount',     app.money_text(v_tax),
        'components',     v_component_json
      )
    );
  end loop;

  -- 8
  if p_prices_include_tax then
    v_total := v_subtotal - v_discount_total;
  else
    v_total := v_subtotal - v_discount_total + v_tax_total;
  end if;

  return jsonb_build_object(
    'prices_include_tax', p_prices_include_tax,
    'subtotal',           app.money_text(v_subtotal),
    'discount_total',     app.money_text(v_discount_total),
    'tax_total',          app.money_text(v_tax_total),
    'total',              app.money_text(v_total),
    'lines',              v_out_lines
  );
end;
$$;

comment on function app.compute_order_totals(jsonb, boolean, text, numeric) is
  'The normative total computation (DATABASE.md §10), including the immutable '
  'multi-component tax snapshot (D31). Both the inclusive and exclusive '
  'branches are implemented; the pilot runs inclusive (D32). Worked vectors: '
  'DATABASE.md §16.5.';

-- ── Inventory reconciliation ─────────────────────────────────────────────────
-- product_stock must always equal the sum of movements (D20). This is the
-- reconciliation query DATABASE.md §7 requires to exist.

create function app.product_stock_drift(p_arena_id uuid)
returns table (product_id uuid, materialised numeric, derived numeric)
language sql
stable
security definer
set search_path = pg_catalog, public, app
as $$
  select p.id,
         coalesce(ps.quantity, 0),
         coalesce(m.total, 0)
    from public.products p
    left join public.product_stock ps
      on ps.product_id = p.id and ps.arena_id = p.arena_id
    left join (
      select im.product_id, im.arena_id, sum(im.quantity) as total
        from public.inventory_movements im
       where im.arena_id = p_arena_id
       group by im.product_id, im.arena_id
    ) m on m.product_id = p.id and m.arena_id = p.arena_id
   where p.arena_id = p_arena_id
     and coalesce(ps.quantity, 0) is distinct from coalesce(m.total, 0);
$$;

comment on function app.product_stock_drift(uuid) is
  'Returns products whose materialised stock disagrees with the sum of their '
  'movements. Should always be empty (D20, DATABASE.md §7).';

revoke all on all functions in schema app from public;
