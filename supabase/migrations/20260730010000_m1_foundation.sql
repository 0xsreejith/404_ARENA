-- M1 — foundation.
--
-- Extensions, the internal `app` helper schema, and the generic triggers every
-- later migration attaches to tables. Nothing here is tenant data and nothing
-- here is exposed to PostgREST.
--
-- Governing: DATABASE.md §1, §2, §13 · SECURITY.md §1, §5 · D03, D17, D21.

-- ── Extensions ───────────────────────────────────────────────────────────────
--
-- pg_trgm  — member name search (DATABASE.md §13)
-- btree_gin — the multicolumn GIN index mixing arena_id with a trigram column
--
-- gen_random_uuid() is in pg_catalog on PostgreSQL 14+, so pgcrypto is not
-- required for identifier generation (DATABASE.md §13).

create extension if not exists pg_trgm with schema extensions;
create extension if not exists btree_gin with schema extensions;

-- ── The `app` schema ─────────────────────────────────────────────────────────
--
-- Internal helpers and trigger functions. Deliberately NOT in the PostgREST
-- exposed schema list (DATABASE.md §1.2), so nothing in here is callable over
-- the wire even when a client knows its name.

create schema if not exists app;

comment on schema app is
  'Internal helper and trigger functions (DATABASE.md §1.2). Never exposed to '
  'PostgREST. `authenticated` holds USAGE only so RLS policies can call the '
  'two membership helpers; EXECUTE is granted function by function.';

revoke all on schema app from public;
grant usage on schema app to authenticated, service_role;

-- Functions are created EXECUTE-to-PUBLIC by default. Flip that default now so
-- a future helper cannot become client-callable by omission (SECURITY.md §5).
alter default privileges in schema app revoke execute on functions from public;

-- ── Generic triggers ─────────────────────────────────────────────────────────

create function app.touch_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog, public, app
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

comment on function app.touch_updated_at() is
  'Maintains updated_at. Every syncable table carries it because sync_pull '
  'uses it as a watermark (D17, OFFLINE.md §8).';

create function app.forbid_mutation()
returns trigger
language plpgsql
set search_path = pg_catalog, public, app
as $$
begin
  -- Raised for EVERY role, including the RPC definer and service_role. This is
  -- deliberately stronger than revoking privileges: it also protects against a
  -- mistake inside a SECURITY DEFINER function (SECURITY.md §10, D21).
  raise exception 'invalid_state: % is append-only and rejects % (D21)',
    tg_table_name, tg_op
    using errcode = 'P0001';
end;
$$;

comment on function app.forbid_mutation() is
  'BEFORE UPDATE OR DELETE guard for payments, inventory_movements and '
  'audit_logs. Corrections are new rows (D21).';

create function app.forbid_business_date_change()
returns trigger
language plpgsql
set search_path = pg_catalog, public, app
as $$
begin
  if new.business_date is distinct from old.business_date then
    raise exception 'invalid_state: business_date is immutable on % (D09)', tg_table_name
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

comment on function app.forbid_business_date_change() is
  'business_date is set server-side at insert and never moves afterwards (D09). '
  'All operational reporting groups by it, so a mutable value would silently '
  'rewrite history.';
