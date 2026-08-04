-- M1 — schema shape.
--
-- Structural properties that hold regardless of data: standard columns, money
-- types, composite tenant keys, the no-CASCADE rule, and the partial unique
-- indexes the product depends on.
--
-- Governing: DATABASE.md §1, §13 · D01, D03, D17.

begin;
set local search_path to extensions, public, pg_catalog;

select plan(21);

-- ── Standard columns (DATABASE.md §1.3) ──────────────────────────────────────

select is_empty(
  $$
    select t.table_name
      from information_schema.tables t
     where t.table_schema = 'public'
       and t.table_type = 'BASE TABLE'
       -- arenas IS the tenant; the other three are not tenant-owned
       -- (DATABASE.md §1.3).
       and t.table_name not in ('arenas', 'organizations', 'profiles', 'permissions')
       and not exists (
         select 1 from information_schema.columns c
          where c.table_schema = 'public' and c.table_name = t.table_name
            and c.column_name = 'arena_id' and c.is_nullable = 'NO'
       )
  $$,
  'every tenant-owned table carries arena_id NOT NULL (D02)'
);

select is_empty(
  $$
    select t.table_name
      from information_schema.tables t
     where t.table_schema = 'public'
       and t.table_type = 'BASE TABLE'
       and exists (
         select 1 from information_schema.columns c
          where c.table_schema = 'public' and c.table_name = t.table_name
            and c.column_name = 'id'
       )
       and exists (
         select 1 from information_schema.columns c
          where c.table_schema = 'public' and c.table_name = t.table_name
            and c.column_name = 'arena_id'
       )
       and not exists (
         select 1
           from pg_constraint con
           join pg_class rel on rel.oid = con.conrelid
           join pg_namespace ns on ns.oid = rel.relnamespace
          where ns.nspname = 'public'
            and rel.relname = t.table_name
            and con.contype = 'u'
            and array(
                  select a.attname::text
                    from unnest(con.conkey) k
                    join pg_attribute a
                      on a.attrelid = con.conrelid and a.attnum = k
                   order by a.attname
                ) = array['arena_id', 'id']
       )
  $$,
  'every tenant-owned table declares UNIQUE (id, arena_id) as a composite FK target (D03)'
);

select is_empty(
  $$
    select t.table_name
      from information_schema.tables t
     where t.table_schema = 'public'
       and t.table_type = 'BASE TABLE'
       and t.table_name not in (
         'permissions', 'role_permissions',
         'payments', 'inventory_movements', 'audit_logs', 'idempotency_keys'
       )
       and not exists (
         select 1 from information_schema.columns c
          where c.table_schema = 'public' and c.table_name = t.table_name
            and c.column_name = 'updated_at' and c.is_nullable = 'NO'
       )
  $$,
  'updated_at NOT NULL everywhere except the documented exceptions (D17, DATABASE.md §1.3)'
);

select is_empty(
  $$
    select c.table_name
      from information_schema.columns c
     where c.table_schema = 'public'
       and c.column_name = 'updated_at'
       and c.table_name in ('payments', 'inventory_movements', 'audit_logs')
  $$,
  'append-only tables have no updated_at — a row never changes (DATABASE.md §1.7)'
);

select is_empty(
  $$
    select t.table_name
      from unnest(array[
        'zones', 'station_types', 'stations', 'games', 'products',
        'billing_plans', 'tax_rates', 'tax_rate_components', 'members', 'roles'
      ]) as t(table_name)
     where not exists (
       select 1 from information_schema.columns c
        where c.table_schema = 'public' and c.table_name = t.table_name
          and c.column_name = 'deleted_at'
     )
  $$,
  'every catalogue table soft-deletes via deleted_at (D17)'
);

select is_empty(
  $$
    select t.table_name
      from unnest(array[
        'shifts', 'sessions', 'orders', 'payments', 'inventory_movements', 'audit_logs'
      ]) as t(table_name)
     where not exists (
       select 1 from information_schema.columns c
        where c.table_schema = 'public' and c.table_name = t.table_name
          and c.column_name = 'business_date'
          and c.data_type = 'date' and c.is_nullable = 'NO'
     )
  $$,
  'business_date is stored NOT NULL on every financial and operational table (D09)'
);

-- ── Money never touches floating point (D01) ─────────────────────────────────

select is_empty(
  $$
    select c.table_name || '.' || c.column_name
      from information_schema.columns c
     where c.table_schema = 'public'
       and c.udt_name in ('float4', 'float8', 'money')
  $$,
  'no float, double precision or money column exists anywhere in public (D01)'
);

select is_empty(
  $$
    with expected(table_name, column_name, precision, scale) as (values
      ('billing_plans', 'hourly_rate', 12, 2),
      ('billing_plans', 'fixed_price', 12, 2),
      ('products', 'selling_price', 12, 2),
      ('products', 'cost_price', 12, 2),
      ('products', 'low_stock_threshold', 12, 3),
      ('product_stock', 'quantity', 12, 3),
      ('shifts', 'opening_float', 12, 2),
      ('shifts', 'expected_cash', 12, 2),
      ('shifts', 'counted_cash', 12, 2),
      ('shifts', 'variance', 12, 2),
      ('orders', 'subtotal', 12, 2),
      ('orders', 'discount_value', 12, 2),
      ('orders', 'discount_total', 12, 2),
      ('orders', 'tax_total', 12, 2),
      ('orders', 'total', 12, 2),
      ('orders', 'paid_total', 12, 2),
      ('orders', 'balance_due', 12, 2),
      ('order_items', 'quantity', 12, 3),
      ('order_items', 'unit_price', 12, 2),
      ('order_items', 'line_subtotal', 12, 2),
      ('order_items', 'discount_amount', 12, 2),
      ('order_items', 'taxable_amount', 12, 2),
      ('order_items', 'tax_amount', 12, 2),
      ('order_items', 'line_total', 12, 2),
      ('payments', 'amount', 12, 2),
      ('inventory_movements', 'quantity', 12, 3),
      ('inventory_movements', 'unit_cost', 12, 2),
      ('tax_rates', 'percent', 5, 2),
      ('tax_rate_components', 'percent', 5, 2)
    )
    select e.table_name || '.' || e.column_name
      from expected e
      left join information_schema.columns c
        on c.table_schema = 'public'
       and c.table_name = e.table_name
       and c.column_name = e.column_name
     where c.udt_name is distinct from 'numeric'
        or c.numeric_precision is distinct from e.precision
        or c.numeric_scale is distinct from e.scale
  $$,
  'money is numeric(12,2), percentages numeric(5,2), quantities numeric(12,3) (D01)'
);

-- ── Composite tenant foreign keys (D03) ──────────────────────────────────────

select is_empty(
  $$
    select con.conname::text
      from pg_constraint con
      join pg_class child on child.oid = con.conrelid
      join pg_namespace nchild on nchild.oid = child.relnamespace
      join pg_class parent on parent.oid = con.confrelid
      join pg_namespace nparent on nparent.oid = parent.relnamespace
     where con.contype = 'f'
       and nchild.nspname = 'public'
       and nparent.nspname = 'public'
       and exists (
         select 1 from information_schema.columns c
          where c.table_schema = 'public' and c.table_name = child.relname
            and c.column_name = 'arena_id'
       )
       and exists (
         select 1 from information_schema.columns c
          where c.table_schema = 'public' and c.table_name = parent.relname
            and c.column_name = 'arena_id'
       )
       and not exists (
         select 1
           from unnest(con.conkey) k
           join pg_attribute a on a.attrelid = con.conrelid and a.attnum = k
          where a.attname = 'arena_id'
       )
  $$,
  'every foreign key between two tenant-owned tables includes arena_id (D03)'
);

select is_empty(
  $$
    select con.conname::text
      from pg_constraint con
      join pg_class rel on rel.oid = con.conrelid
      join pg_namespace ns on ns.oid = rel.relnamespace
     where con.contype = 'f'
       and ns.nspname = 'public'
       and con.confdeltype <> 'r'
  $$,
  'every foreign key is ON DELETE RESTRICT — no CASCADE exists in P0 (DATABASE.md §1.6)'
);

-- ── The constraints the product actually depends on ──────────────────────────

select has_index(
  'public', 'sessions', 'sessions_one_live_per_station',
  'the partial unique index enforcing one live session per station exists (OFFLINE.md §4)'
);

select has_index(
  'public', 'shifts', 'shifts_one_open_per_arena',
  'the partial unique index enforcing one open shift per arena exists (D30)'
);

select has_index(
  'public', 'orders', 'orders_one_live_per_session',
  'one non-void order per session (D07)'
);

select has_index(
  'public', 'order_items', 'order_items_one_play_line_per_order',
  'at most one play line per order (DATABASE.md §10)'
);

select has_index(
  'public', 'members', 'members_arena_phone_live_idx',
  'member phone is unique per arena on the canonical form (D36)'
);

select has_index(
  'public', 'members', 'members_arena_full_name_trgm_idx',
  'the trigram index backing member name search exists (DATABASE.md §13)'
);

-- ── Generated and trigger-maintained columns ─────────────────────────────────

select col_is_null('public', 'orders', 'receipt_number', 'receipt_number is null until settlement');

select is(
  (select is_generated from information_schema.columns
    where table_schema = 'public' and table_name = 'orders' and column_name = 'balance_due'),
  'ALWAYS',
  'orders.balance_due is a generated column over total - paid_total (D07)'
);

select is(
  (select is_generated from information_schema.columns
    where table_schema = 'public' and table_name = 'shifts' and column_name = 'variance'),
  'ALWAYS',
  'shifts.variance is a generated column over counted_cash - expected_cash (DATABASE.md §8)'
);

-- ── Enumerations are text + CHECK, never PostgreSQL enum types ───────────────

select is_empty(
  $$
    select t.typname::text
      from pg_type t
      join pg_namespace n on n.oid = t.typnamespace
     where n.nspname = 'public' and t.typtype = 'e'
  $$,
  'no PostgreSQL enum types: enumerations are text + CHECK (DATABASE.md §1.1)'
);

-- ── Every foreign key column is indexed (DATABASE.md §13) ────────────────────

select is_empty(
  $$
    select con.conname::text
      from pg_constraint con
      join pg_class rel on rel.oid = con.conrelid
      join pg_namespace ns on ns.oid = rel.relnamespace
     where con.contype = 'f'
       and ns.nspname = 'public'
       and not exists (
         select 1
           from pg_index i
          where i.indrelid = con.conrelid
            and (i.indkey::int2[])[0:array_length(con.conkey, 1) - 1] @> array[con.conkey[1]]
       )
  $$,
  'every foreign key has an index whose leading column is the first key column'
);

select * from finish();
rollback;
