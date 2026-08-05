-- Migration: 20260805092000_epic10c_wallet_loyalty.sql
-- Description: Wave C — memberships, wallets, loyalty ledgers + settle hooks.
-- Spec: commercial DATABASE_SCHEMA §2.3 · D01 · D21 · D28a

-- ── Permissions ──────────────────────────────────────────────────────────────

insert into public.permissions (code, description, category) values
  ('member.wallet',      'View and adjust member wallets',              'members'),
  ('loyalty.adjust',     'Manually adjust loyalty points',              'members'),
  ('membership.manage',  'Create plans and manage memberships',         'members')
on conflict (code) do nothing;

-- Grant new codes to existing owner roles; managers get membership + loyalty
insert into public.role_permissions (arena_id, role_id, permission_code)
select r.arena_id, r.id, p.code
  from public.roles r
 cross join (values
   ('member.wallet'), ('loyalty.adjust'), ('membership.manage')
 ) as p(code)
 where r.code = 'owner' and r.deleted_at is null
on conflict do nothing;

insert into public.role_permissions (arena_id, role_id, permission_code)
select r.arena_id, r.id, p.code
  from public.roles r
 cross join (values ('member.wallet'), ('loyalty.adjust'), ('membership.manage')) as p(code)
 where r.code = 'manager' and r.deleted_at is null
on conflict do nothing;

-- Update provision_arena staff/manager arrays via replace of function body end —
-- additive grant for new arenas: owners get all via select from permissions.
-- Managers: patch provision_arena manager extras.

create or replace function public.provision_arena(
  p_organization_id         uuid,
  p_name                    text,
  p_timezone                text,
  p_currency                text,
  p_default_phone_dial_code text,
  p_owner_user_id           uuid
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_arena_id       uuid;
  v_owner_role_id  uuid;
  v_manager_role_id uuid;
  v_staff_role_id  uuid;
  v_tax_rate_id    uuid;
  v_staff_codes    text[] := array[
    'session.view', 'session.start', 'session.pause', 'session.resume',
    'session.extend', 'session.stop',
    'station.view',
    'member.view', 'member.create',
    'product.view', 'inventory.view', 'inventory.sell',
    'shift.view', 'shift.open',
    'payment.create', 'payment.view'
  ];
  v_manager_extra_codes text[] := array[
    'session.cancel',
    'station.update', 'station.maintenance',
    'member.update', 'member.block', 'member.wallet', 'loyalty.adjust', 'membership.manage',
    'product.manage', 'inventory.adjust', 'inventory.receive',
    'shift.close',
    'discount.apply', 'order.void',
    'report.view', 'staff.view'
  ];
begin
  if p_name is null or btrim(p_name) = '' then
    raise exception 'validation_failed: an arena name is required'
      using errcode = 'P0001';
  end if;

  if not exists (select 1 from public.organizations o where o.id = p_organization_id) then
    raise exception 'not_found: organization %', p_organization_id
      using errcode = 'P0001';
  end if;

  if not exists (select 1 from public.profiles pr where pr.id = p_owner_user_id) then
    raise exception 'not_found: owner profile %', p_owner_user_id
      using errcode = 'P0001';
  end if;

  if not exists (select 1 from pg_catalog.pg_timezone_names t where t.name = p_timezone) then
    raise exception 'validation_failed: % is not a known IANA timezone', p_timezone
      using errcode = 'P0001';
  end if;

  if p_currency !~ '^[A-Z]{3}$' then
    raise exception 'validation_failed: % is not an ISO 4217 currency code', p_currency
      using errcode = 'P0001';
  end if;

  if p_default_phone_dial_code !~ '^\+[1-9][0-9]{0,3}$' then
    raise exception 'validation_failed: % is not a valid dial code', p_default_phone_dial_code
      using errcode = 'P0001';
  end if;

  insert into public.arenas (organization_id, name, timezone, currency)
  values (p_organization_id, btrim(p_name), p_timezone, p_currency)
  returning id into v_arena_id;

  insert into public.arena_settings (arena_id, default_phone_dial_code)
  values (v_arena_id, p_default_phone_dial_code);

  insert into public.roles (arena_id, code, name, is_system)
  values (v_arena_id, 'owner', 'Owner', true)
  returning id into v_owner_role_id;

  insert into public.roles (arena_id, code, name, is_system)
  values (v_arena_id, 'manager', 'Manager', true)
  returning id into v_manager_role_id;

  insert into public.roles (arena_id, code, name, is_system)
  values (v_arena_id, 'staff', 'Staff', true)
  returning id into v_staff_role_id;

  insert into public.role_permissions (arena_id, role_id, permission_code)
  select v_arena_id, v_owner_role_id, p.code
    from public.permissions p;

  insert into public.role_permissions (arena_id, role_id, permission_code)
  select v_arena_id, v_manager_role_id, code
    from unnest(v_staff_codes || v_manager_extra_codes) as code;

  insert into public.role_permissions (arena_id, role_id, permission_code)
  select v_arena_id, v_staff_role_id, code
    from unnest(v_staff_codes) as code;

  insert into public.arena_users (arena_id, user_id, role_id)
  values (v_arena_id, p_owner_user_id, v_owner_role_id);

  insert into public.zones (arena_id, name, sort_order)
  values (v_arena_id, 'Main floor', 0);

  insert into public.tax_rates (arena_id, name)
  values (v_arena_id, 'No tax')
  returning id into v_tax_rate_id;

  insert into public.tax_rate_components (arena_id, tax_rate_id, name, percent, sort_order)
  values (v_arena_id, v_tax_rate_id, 'Tax', 0, 1);

  update public.arena_settings
     set default_play_tax_rate_id = v_tax_rate_id,
         default_product_tax_rate_id = v_tax_rate_id
   where arena_id = v_arena_id;

  perform app.audit(
    v_arena_id,
    'arena_user.changed',
    'arena_user',
    p_owner_user_id,
    jsonb_build_object('reason', 'provisioned', 'role_code', 'owner')
  );

  return v_arena_id;
end;
$$;

-- ── Membership plans ─────────────────────────────────────────────────────────

create table public.membership_plans (
  id            uuid primary key default gen_random_uuid(),
  arena_id      uuid           not null references public.arenas (id) on delete restrict,
  name          text           not null check (length(btrim(name)) > 0),
  price         numeric(12, 2) not null check (price >= 0),
  period_days   int            not null check (period_days > 0),
  benefits_json jsonb          not null default '{}'::jsonb,
  active        boolean        not null default true,
  deleted_at    timestamptz    null,
  created_at    timestamptz    not null default now(),
  updated_at    timestamptz    not null default now(),
  unique (id, arena_id)
);

create trigger membership_plans_touch_updated_at
  before update on public.membership_plans
  for each row execute function app.touch_updated_at();

create table public.member_memberships (
  id         uuid primary key default gen_random_uuid(),
  arena_id   uuid        not null,
  member_id  uuid        not null,
  plan_id    uuid        not null,
  status     text        not null check (status in ('active', 'expired', 'cancelled')),
  starts_at  timestamptz not null,
  ends_at    timestamptz not null,
  created_at timestamptz not null default now(),
  unique (id, arena_id),
  check (ends_at > starts_at),
  foreign key (member_id, arena_id)
    references public.members (id, arena_id) on delete cascade,
  foreign key (plan_id, arena_id)
    references public.membership_plans (id, arena_id) on delete restrict
);

create index member_memberships_member_idx
  on public.member_memberships (arena_id, member_id, status);

-- ── Wallets ──────────────────────────────────────────────────────────────────

create table public.wallets (
  member_id  uuid primary key,
  arena_id   uuid           not null,
  balance    numeric(12, 2) not null default 0 check (balance >= 0),
  updated_at timestamptz    not null default now(),
  unique (member_id, arena_id),
  foreign key (member_id, arena_id)
    references public.members (id, arena_id) on delete cascade
);

create table public.wallet_ledger (
  id                 uuid primary key default gen_random_uuid(),
  arena_id           uuid           not null,
  member_id          uuid           not null,
  entry_type         text           not null check (entry_type in (
    'topup', 'debit', 'refund', 'adjust'
  )),
  amount             numeric(12, 2) not null check (amount <> 0),
  balance_after      numeric(12, 2) not null check (balance_after >= 0),
  order_id           uuid           null,
  payment_id         uuid           null,
  note               text           null,
  actor_user_id      uuid           not null references public.profiles (id) on delete restrict,
  business_date      date           not null,
  created_at         timestamptz    not null default now(),
  unique (id, arena_id),
  foreign key (member_id, arena_id)
    references public.members (id, arena_id) on delete restrict,
  foreign key (order_id, arena_id)
    references public.orders (id, arena_id) on delete restrict,
  foreign key (payment_id, arena_id)
    references public.payments (id, arena_id) on delete restrict
);

create index wallet_ledger_member_idx
  on public.wallet_ledger (arena_id, member_id, created_at desc);

-- Append-only guard
create or replace function app.wallet_ledger_immutable()
returns trigger
language plpgsql
as $$
begin
  raise exception 'immutable: wallet_ledger cannot be updated or deleted'
    using errcode = 'P0001';
end;
$$;

create trigger wallet_ledger_no_update
  before update or delete on public.wallet_ledger
  for each row execute function app.wallet_ledger_immutable();

-- ── Loyalty ──────────────────────────────────────────────────────────────────

create table public.loyalty_tiers (
  id              uuid primary key default gen_random_uuid(),
  arena_id        uuid        not null references public.arenas (id) on delete restrict,
  code            text        not null,
  label           text        not null,
  min_points      int         not null check (min_points >= 0),
  sort_order      int         not null default 0,
  unique (id, arena_id),
  unique (arena_id, code)
);

create table public.loyalty_accounts (
  member_id  uuid primary key,
  arena_id   uuid        not null,
  points     int         not null default 0 check (points >= 0),
  tier_id    uuid        null,
  updated_at timestamptz not null default now(),
  unique (member_id, arena_id),
  foreign key (member_id, arena_id)
    references public.members (id, arena_id) on delete cascade,
  foreign key (tier_id, arena_id)
    references public.loyalty_tiers (id, arena_id) on delete set null
);

create table public.loyalty_ledger (
  id            uuid primary key default gen_random_uuid(),
  arena_id      uuid        not null,
  member_id     uuid        not null,
  entry_type    text        not null check (entry_type in ('earn', 'redeem', 'adjust', 'expire')),
  points        int         not null check (points <> 0),
  points_after  int         not null check (points_after >= 0),
  order_id      uuid        null,
  note          text        null,
  actor_user_id uuid        not null references public.profiles (id) on delete restrict,
  created_at    timestamptz not null default now(),
  unique (id, arena_id),
  foreign key (member_id, arena_id)
    references public.members (id, arena_id) on delete restrict,
  foreign key (order_id, arena_id)
    references public.orders (id, arena_id) on delete restrict
);

create or replace function app.loyalty_ledger_immutable()
returns trigger
language plpgsql
as $$
begin
  raise exception 'immutable: loyalty_ledger cannot be updated or deleted'
    using errcode = 'P0001';
end;
$$;

create trigger loyalty_ledger_no_update
  before update or delete on public.loyalty_ledger
  for each row execute function app.loyalty_ledger_immutable();

-- Seed default tiers for existing arenas
insert into public.loyalty_tiers (arena_id, code, label, min_points, sort_order)
select a.id, t.code, t.label, t.min_points, t.sort_order
  from public.arenas a
 cross join (values
   ('silver', 'Silver', 0, 1),
   ('gold', 'Gold', 500, 2),
   ('diamond', 'Diamond', 2000, 3)
 ) as t(code, label, min_points, sort_order)
on conflict (arena_id, code) do nothing;

create or replace function app.seed_loyalty_tiers()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
begin
  insert into public.loyalty_tiers (arena_id, code, label, min_points, sort_order)
  values
    (new.id, 'silver', 'Silver', 0, 1),
    (new.id, 'gold', 'Gold', 500, 2),
    (new.id, 'diamond', 'Diamond', 2000, 3)
  on conflict (arena_id, code) do nothing;
  return new;
end;
$$;

create trigger arenas_seed_loyalty_tiers
  after insert on public.arenas
  for each row execute function app.seed_loyalty_tiers();

-- Extend member spine for wallet + loyalty
create or replace function app.ensure_member_spine()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_code text;
  v_tier uuid;
begin
  insert into public.member_profiles (member_id, arena_id)
  values (new.id, new.arena_id)
  on conflict (member_id) do nothing;

  v_code := upper(substr(replace(new.id::text, '-', ''), 1, 8));
  insert into public.member_codes (arena_id, member_id, code, kind)
  values (new.arena_id, new.id, v_code, 'public')
  on conflict (arena_id, member_id, kind) do nothing;

  insert into public.member_stats (member_id, arena_id)
  values (new.id, new.arena_id)
  on conflict (member_id) do nothing;

  insert into public.wallets (member_id, arena_id)
  values (new.id, new.arena_id)
  on conflict (member_id) do nothing;

  select t.id into v_tier
    from public.loyalty_tiers t
   where t.arena_id = new.arena_id and t.code = 'silver'
   limit 1;

  insert into public.loyalty_accounts (member_id, arena_id, points, tier_id)
  values (new.id, new.arena_id, 0, v_tier)
  on conflict (member_id) do nothing;

  return new;
end;
$$;

insert into public.wallets (member_id, arena_id)
select m.id, m.arena_id from public.members m
on conflict (member_id) do nothing;

insert into public.loyalty_accounts (member_id, arena_id, points, tier_id)
select m.id, m.arena_id, 0, t.id
  from public.members m
  left join public.loyalty_tiers t
    on t.arena_id = m.arena_id and t.code = 'silver'
on conflict (member_id) do nothing;

-- Allow wallet payment method
alter table public.payments drop constraint if exists payments_method_check;
alter table public.payments
  add constraint payments_method_check
  check (method in ('cash', 'upi', 'card', 'wallet'));

-- RLS revoke
alter table public.membership_plans enable row level security;
alter table public.member_memberships enable row level security;
alter table public.wallets enable row level security;
alter table public.wallet_ledger enable row level security;
alter table public.loyalty_tiers enable row level security;
alter table public.loyalty_accounts enable row level security;
alter table public.loyalty_ledger enable row level security;

revoke all on public.membership_plans from authenticated, anon, public;
revoke all on public.member_memberships from authenticated, anon, public;
revoke all on public.wallets from authenticated, anon, public;
revoke all on public.wallet_ledger from authenticated, anon, public;
revoke all on public.loyalty_tiers from authenticated, anon, public;
revoke all on public.loyalty_accounts from authenticated, anon, public;
revoke all on public.loyalty_ledger from authenticated, anon, public;

-- ── Wallet helpers ───────────────────────────────────────────────────────────

create or replace function app.wallet_apply(
  p_arena_id uuid,
  p_member_id uuid,
  p_entry_type text,
  p_amount numeric,
  p_note text default null,
  p_order_id uuid default null,
  p_payment_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_wallet public.wallets;
  v_new_balance numeric(12,2);
  v_ledger public.wallet_ledger;
begin
  insert into public.wallets (member_id, arena_id)
  values (p_member_id, p_arena_id)
  on conflict (member_id) do nothing;

  select * into v_wallet
    from public.wallets w
   where w.member_id = p_member_id and w.arena_id = p_arena_id
   for update;

  v_new_balance := v_wallet.balance + p_amount;
  if v_new_balance < 0 then
    raise exception 'insufficient_funds: wallet balance %', v_wallet.balance
      using errcode = 'P0001';
  end if;

  update public.wallets
     set balance = v_new_balance, updated_at = now()
   where member_id = p_member_id and arena_id = p_arena_id;

  insert into public.wallet_ledger (
    arena_id, member_id, entry_type, amount, balance_after,
    order_id, payment_id, note, actor_user_id, business_date
  ) values (
    p_arena_id, p_member_id, p_entry_type, p_amount, v_new_balance,
    p_order_id, p_payment_id, p_note, app.current_actor_id(),
    app.business_date(p_arena_id, now())
  )
  returning * into v_ledger;

  return jsonb_build_object(
    'balance', to_char(v_new_balance, 'FM999999990.00'),
    'ledger_id', v_ledger.id,
    'amount', to_char(p_amount, 'FM999999990.00')
  );
end;
$$;

create or replace function app.loyalty_apply(
  p_arena_id uuid,
  p_member_id uuid,
  p_entry_type text,
  p_points int,
  p_note text default null,
  p_order_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_acct public.loyalty_accounts;
  v_new int;
  v_tier uuid;
begin
  insert into public.loyalty_accounts (member_id, arena_id)
  values (p_member_id, p_arena_id)
  on conflict (member_id) do nothing;

  select * into v_acct
    from public.loyalty_accounts a
   where a.member_id = p_member_id and a.arena_id = p_arena_id
   for update;

  v_new := v_acct.points + p_points;
  if v_new < 0 then
    raise exception 'insufficient_funds: loyalty points %', v_acct.points
      using errcode = 'P0001';
  end if;

  select t.id into v_tier
    from public.loyalty_tiers t
   where t.arena_id = p_arena_id
     and t.min_points <= v_new
   order by t.min_points desc
   limit 1;

  update public.loyalty_accounts
     set points = v_new, tier_id = v_tier, updated_at = now()
   where member_id = p_member_id and arena_id = p_arena_id;

  insert into public.loyalty_ledger (
    arena_id, member_id, entry_type, points, points_after,
    order_id, note, actor_user_id
  ) values (
    p_arena_id, p_member_id, p_entry_type, p_points, v_new,
    p_order_id, p_note, app.current_actor_id()
  );

  return jsonb_build_object('points', v_new, 'tier_id', v_tier);
end;
$$;

-- ── Public wallet RPCs ───────────────────────────────────────────────────────

create or replace function public.wallet_topup(
  p_arena_id uuid,
  p_member_id uuid,
  p_amount numeric,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
begin
  perform app.require_permission(p_arena_id, 'member.wallet');
  if p_amount is null or p_amount <= 0 then
    raise exception 'validation_failed: topup amount must be positive'
      using errcode = 'P0001';
  end if;
  return app.wallet_apply(p_arena_id, p_member_id, 'topup', p_amount, p_note);
end;
$$;

grant execute on function public.wallet_topup(uuid, uuid, numeric, text) to authenticated;

create or replace function public.wallet_debit(
  p_arena_id uuid,
  p_member_id uuid,
  p_amount numeric,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
begin
  perform app.require_permission(p_arena_id, 'member.wallet');
  if p_amount is null or p_amount <= 0 then
    raise exception 'validation_failed: debit amount must be positive'
      using errcode = 'P0001';
  end if;
  return app.wallet_apply(p_arena_id, p_member_id, 'debit', -p_amount, p_note);
end;
$$;

grant execute on function public.wallet_debit(uuid, uuid, numeric, text) to authenticated;

create or replace function public.wallet_refund(
  p_arena_id uuid,
  p_member_id uuid,
  p_amount numeric,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
begin
  perform app.require_permission(p_arena_id, 'member.wallet');
  if p_amount is null or p_amount <= 0 then
    raise exception 'validation_failed: refund amount must be positive'
      using errcode = 'P0001';
  end if;
  return app.wallet_apply(p_arena_id, p_member_id, 'refund', p_amount, p_note);
end;
$$;

grant execute on function public.wallet_refund(uuid, uuid, numeric, text) to authenticated;

create or replace function public.wallet_history(
  p_arena_id uuid,
  p_member_id uuid,
  p_limit int default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_limit int := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_bal numeric(12,2);
  v_rows jsonb;
begin
  perform app.require_permission(p_arena_id, 'member.wallet');

  select w.balance into v_bal
    from public.wallets w
   where w.member_id = p_member_id and w.arena_id = p_arena_id;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', l.id,
           'entry_type', l.entry_type,
           'amount', to_char(l.amount, 'FM999999990.00'),
           'balance_after', to_char(l.balance_after, 'FM999999990.00'),
           'note', l.note,
           'created_at', l.created_at
         ) order by l.created_at desc), '[]'::jsonb)
    into v_rows
    from (
      select * from public.wallet_ledger wl
       where wl.arena_id = p_arena_id and wl.member_id = p_member_id
       order by wl.created_at desc
       limit v_limit
    ) l;

  return jsonb_build_object(
    'balance', to_char(coalesce(v_bal, 0), 'FM999999990.00'),
    'entries', coalesce(v_rows, '[]'::jsonb)
  );
end;
$$;

grant execute on function public.wallet_history(uuid, uuid, int) to authenticated;

create or replace function public.loyalty_balance(
  p_arena_id uuid,
  p_member_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_acct public.loyalty_accounts;
  v_tier public.loyalty_tiers;
begin
  perform app.require_permission(p_arena_id, 'member.view');

  select * into v_acct from public.loyalty_accounts
   where member_id = p_member_id and arena_id = p_arena_id;

  if v_acct.tier_id is not null then
    select * into v_tier from public.loyalty_tiers
     where id = v_acct.tier_id and arena_id = p_arena_id;
  end if;

  return jsonb_build_object(
    'points', coalesce(v_acct.points, 0),
    'tier', case when v_tier.id is null then null else jsonb_build_object(
      'id', v_tier.id, 'code', v_tier.code, 'label', v_tier.label
    ) end
  );
end;
$$;

grant execute on function public.loyalty_balance(uuid, uuid) to authenticated;

create or replace function public.loyalty_adjust(
  p_arena_id uuid,
  p_member_id uuid,
  p_points int,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
begin
  perform app.require_permission(p_arena_id, 'loyalty.adjust');
  if p_points is null or p_points = 0 then
    raise exception 'validation_failed: points delta required'
      using errcode = 'P0001';
  end if;
  return app.loyalty_apply(
    p_arena_id, p_member_id,
    case when p_points > 0 then 'adjust' else 'adjust' end,
    p_points, p_note
  );
end;
$$;

grant execute on function public.loyalty_adjust(uuid, uuid, int, text) to authenticated;

-- ── Membership RPCs ──────────────────────────────────────────────────────────

create or replace function public.membership_plan_list(p_arena_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_rows jsonb;
begin
  perform app.require_permission(p_arena_id, 'membership.manage');

  select coalesce(jsonb_agg(to_jsonb(p) order by p.name), '[]'::jsonb)
    into v_rows
    from public.membership_plans p
   where p.arena_id = p_arena_id and p.deleted_at is null;

  return jsonb_build_object('plans', coalesce(v_rows, '[]'::jsonb));
end;
$$;

grant execute on function public.membership_plan_list(uuid) to authenticated;

create or replace function public.membership_plan_upsert(
  p_arena_id uuid,
  p_plan_id uuid,
  p_name text,
  p_price numeric,
  p_period_days int,
  p_benefits_json jsonb default '{}'::jsonb,
  p_active boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_plan public.membership_plans;
begin
  perform app.require_permission(p_arena_id, 'membership.manage');

  insert into public.membership_plans (
    id, arena_id, name, price, period_days, benefits_json, active
  ) values (
    coalesce(p_plan_id, gen_random_uuid()), p_arena_id, btrim(p_name),
    p_price, p_period_days, coalesce(p_benefits_json, '{}'::jsonb), coalesce(p_active, true)
  )
  on conflict (id) do update set
    name = excluded.name,
    price = excluded.price,
    period_days = excluded.period_days,
    benefits_json = excluded.benefits_json,
    active = excluded.active
  where public.membership_plans.arena_id = p_arena_id
  returning * into v_plan;

  return to_jsonb(v_plan);
end;
$$;

grant execute on function public.membership_plan_upsert(uuid, uuid, text, numeric, int, jsonb, boolean)
  to authenticated;

create or replace function public.membership_subscribe(
  p_arena_id uuid,
  p_member_id uuid,
  p_plan_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_plan public.membership_plans;
  v_mem public.member_memberships;
begin
  perform app.require_permission(p_arena_id, 'membership.manage');

  select * into v_plan from public.membership_plans
   where id = p_plan_id and arena_id = p_arena_id and deleted_at is null and active;

  if v_plan.id is null then
    raise exception 'not_found: membership plan' using errcode = 'P0001';
  end if;

  update public.member_memberships
     set status = 'cancelled'
   where arena_id = p_arena_id and member_id = p_member_id and status = 'active';

  insert into public.member_memberships (
    arena_id, member_id, plan_id, status, starts_at, ends_at
  ) values (
    p_arena_id, p_member_id, p_plan_id, 'active', now(),
    now() + make_interval(days => v_plan.period_days)
  )
  returning * into v_mem;

  return to_jsonb(v_mem);
end;
$$;

grant execute on function public.membership_subscribe(uuid, uuid, uuid) to authenticated;

create or replace function public.membership_cancel(
  p_arena_id uuid,
  p_membership_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_mem public.member_memberships;
begin
  perform app.require_permission(p_arena_id, 'membership.manage');

  update public.member_memberships
     set status = 'cancelled'
   where id = p_membership_id and arena_id = p_arena_id and status = 'active'
  returning * into v_mem;

  if v_mem.id is null then
    raise exception 'not_found: active membership' using errcode = 'P0001';
  end if;

  return to_jsonb(v_mem);
end;
$$;

grant execute on function public.membership_cancel(uuid, uuid) to authenticated;

-- ── Extend member_get with wallet / loyalty / membership ─────────────────────

create or replace function public.member_get(
  p_arena_id  uuid,
  p_member_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_member public.members;
  v_sessions jsonb;
  v_profile jsonb;
  v_stats jsonb;
  v_tags jsonb;
  v_code text;
  v_outstanding numeric(12,2);
  v_wallet numeric(12,2);
  v_loyalty jsonb;
  v_membership jsonb;
begin
  perform app.require_permission(p_arena_id, 'member.view');

  select * into v_member
    from public.members m
   where m.id = p_member_id
     and m.arena_id = p_arena_id
     and m.deleted_at is null;

  if v_member.id is null then
    raise exception 'not_found: member'
      using errcode = 'P0001';
  end if;

  perform app.member_stats_refresh(p_arena_id, p_member_id);

  select to_jsonb(mp) - 'member_id' - 'arena_id'
    into v_profile
    from public.member_profiles mp
   where mp.member_id = p_member_id and mp.arena_id = p_arena_id;

  select to_jsonb(ms) - 'member_id' - 'arena_id'
    into v_stats
    from public.member_stats ms
   where ms.member_id = p_member_id and ms.arena_id = p_arena_id;

  select mc.code into v_code
    from public.member_codes mc
   where mc.member_id = p_member_id and mc.arena_id = p_arena_id and mc.kind = 'public';

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', t.id, 'code', t.code, 'label', t.label, 'color', t.color
         ) order by t.label), '[]'::jsonb)
    into v_tags
    from public.member_tag_assignments a
    join public.member_tags t on t.id = a.tag_id and t.arena_id = a.arena_id
   where a.arena_id = p_arena_id and a.member_id = p_member_id;

  select coalesce(sum(o.total - o.paid_total), 0)
    into v_outstanding
    from public.orders o
   where o.arena_id = p_arena_id
     and o.member_id = p_member_id
     and o.status = 'open';

  select w.balance into v_wallet
    from public.wallets w
   where w.member_id = p_member_id and w.arena_id = p_arena_id;

  select public.loyalty_balance(p_arena_id, p_member_id) into v_loyalty;

  select to_jsonb(mm) || jsonb_build_object('plan_name', mp.name)
    into v_membership
    from public.member_memberships mm
    join public.membership_plans mp on mp.id = mm.plan_id and mp.arena_id = mm.arena_id
   where mm.arena_id = p_arena_id and mm.member_id = p_member_id and mm.status = 'active'
   order by mm.ends_at desc
   limit 1;

  select coalesce(jsonb_agg(row_to_json(s)::jsonb order by s.started_at desc), '[]'::jsonb)
    into v_sessions
    from (
      select
        sess.id,
        sess.status,
        sess.started_at,
        sess.ended_at,
        st.name as station_name,
        g.title as game_title,
        sess.business_date
      from public.sessions sess
      left join public.stations st
        on st.id = sess.station_id and st.arena_id = sess.arena_id
      left join public.games g
        on g.id = sess.game_id and g.arena_id = sess.arena_id
      where sess.arena_id = p_arena_id
        and sess.member_id = p_member_id
      order by sess.started_at desc
      limit 10
    ) s;

  return app.member_to_json(v_member)
    || jsonb_build_object(
      'member_code', v_code,
      'profile', coalesce(v_profile, '{}'::jsonb),
      'stats', coalesce(v_stats, '{}'::jsonb),
      'tags', coalesce(v_tags, '[]'::jsonb),
      'outstanding_balance', to_char(v_outstanding, 'FM999999990.00'),
      'wallet_balance', to_char(coalesce(v_wallet, 0), 'FM999999990.00'),
      'loyalty', coalesce(v_loyalty, jsonb_build_object('points', 0)),
      'membership', v_membership,
      'recent_sessions', v_sessions
    );
end;
$$;

-- ── order_settle with wallet + loyalty earn ──────────────────────────────────

create or replace function public.order_settle(
  p_arena_id        uuid,
  p_order_id        uuid,
  p_payment_id      uuid,
  p_payment_method  text,
  p_amount          numeric,
  p_reference       text default null,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
declare
  v_order          record;
  v_shift_id       uuid;
  v_preview        jsonb;
  v_receipt        record;
  v_new_paid_total numeric(12,2);
  v_total          numeric(12,2);
  v_replay         jsonb;
  v_fingerprint    text;
  v_response       jsonb;
  v_status         text;
  v_line           jsonb;
  v_i              int;
  v_earn_points    int;
begin
  perform app.require_permission(p_arena_id, 'payment.create');

  if p_idempotency_key is not null and btrim(p_idempotency_key) <> '' then
    v_fingerprint := md5(
      p_order_id::text || p_payment_id::text || p_payment_method
      || app.money_text(p_amount) || coalesce(p_reference, '')
    );
    v_replay := app.claim_idempotency(
      p_arena_id, p_idempotency_key, 'order_settle', v_fingerprint
    );
    if v_replay is not null then
      return v_replay;
    end if;
  end if;

  if p_payment_method not in ('cash', 'card', 'upi', 'wallet') then
    raise exception 'validation_failed: invalid payment method %', p_payment_method
      using errcode = 'P0001';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'validation_failed: payment amount must be positive'
      using errcode = 'P0001';
  end if;

  select * into v_order
    from public.orders
   where id = p_order_id and arena_id = p_arena_id;

  if v_order.id is null then
    raise exception 'not_found: order %', p_order_id using errcode = 'P0001';
  end if;

  if v_order.status = 'settled' then
    v_response := jsonb_build_object(
      'id', p_order_id,
      'status', 'settled',
      'receipt_number', v_order.receipt_number,
      'paid_total', v_order.paid_total
    );
    if p_idempotency_key is not null and btrim(p_idempotency_key) <> '' then
      perform app.complete_idempotency(p_arena_id, p_idempotency_key, v_response);
    end if;
    return v_response;
  end if;

  if v_order.status = 'void' then
    raise exception 'invalid_state: cannot settle voided order'
      using errcode = 'P0001';
  end if;

  v_shift_id := app.current_shift_id(p_arena_id);
  if v_shift_id is null then
    raise exception 'invalid_state: an open shift is required for cash reconciliation'
      using errcode = 'P0001';
  end if;

  if p_payment_method = 'wallet' and v_order.member_id is null then
    raise exception 'validation_failed: wallet payment requires a member on the order'
      using errcode = 'P0001';
  end if;

  -- Insert payment first so wallet_ledger can reference it; same txn rolls back on debit fail.
  insert into public.payments (
    id, arena_id, order_id, shift_id, method, amount, reference,
    actor_user_id, business_date
  )
  values (
    p_payment_id, p_arena_id, p_order_id, v_shift_id, p_payment_method, p_amount,
    p_reference, app.current_actor_id(), v_order.business_date
  );

  if p_payment_method = 'wallet' then
    perform app.wallet_apply(
      p_arena_id, v_order.member_id, 'debit', -p_amount,
      'order settle', p_order_id, p_payment_id
    );
  end if;

  v_preview := public.order_preview(p_arena_id, p_order_id);
  v_new_paid_total := (v_preview->>'paid_total')::numeric;
  v_total := (v_preview->>'total')::numeric;
  v_status := 'open';

  if v_new_paid_total >= v_total then
    select * into v_receipt
      from app.next_receipt_number(p_arena_id, v_order.business_date);

    update public.orders
       set status = 'settled',
           subtotal = (v_preview->>'subtotal')::numeric,
           discount_total = (v_preview->>'discount_total')::numeric,
           tax_total = (v_preview->>'tax_total')::numeric,
           total = v_total,
           receipt_sequence = v_receipt.sequence_number,
           receipt_number = v_receipt.formatted_number,
           settled_by_user_id = app.current_actor_id(),
           settled_at = now()
     where id = p_order_id and arena_id = p_arena_id;

    for v_i in 0 .. greatest(jsonb_array_length(coalesce(v_preview->'items', '[]'::jsonb)) - 1, -1)
    loop
      v_line := v_preview->'items'->v_i;
      update public.order_items
         set taxable_amount = (v_line->>'taxable_amount')::numeric,
             tax_amount = (v_line->>'tax_amount')::numeric,
             line_total = (v_line->>'line_total')::numeric,
             tax_rate_snapshot = coalesce(
               v_line->'tax_rate_snapshot', tax_rate_snapshot
             )
       where id = (v_line->>'id')::uuid
         and arena_id = p_arena_id
         and order_id = p_order_id;
    end loop;

    insert into public.inventory_movements (
      id, arena_id, product_id, type, quantity, order_id, order_item_id,
      actor_user_id, business_date
    )
    select gen_random_uuid(), p_arena_id, oi.product_id, 'sale', -oi.quantity,
           p_order_id, oi.id, app.current_actor_id(), v_order.business_date
      from public.order_items oi
     where oi.order_id = p_order_id
       and oi.arena_id = p_arena_id
       and oi.type = 'product';

    -- Loyalty: 1 point per whole currency unit of settled total
    if v_order.member_id is not null then
      v_earn_points := floor(v_total)::int;
      if v_earn_points > 0 then
        perform app.loyalty_apply(
          p_arena_id, v_order.member_id, 'earn', v_earn_points,
          'order settle earn', p_order_id
        );
      end if;
      perform app.member_stats_refresh(p_arena_id, v_order.member_id);
    end if;

    perform app.audit(
      p_arena_id, 'order.settled', 'order', p_order_id,
      jsonb_build_object(
        'receipt_number', v_receipt.formatted_number,
        'total', app.money_text(v_total),
        'method', p_payment_method
      )
    );

    v_status := 'settled';
    v_response := jsonb_build_object(
      'id', p_order_id,
      'status', 'settled',
      'receipt_number', v_receipt.formatted_number,
      'paid_total', v_new_paid_total
    );
  else
    v_response := jsonb_build_object(
      'id', p_order_id,
      'status', 'open',
      'receipt_number', null,
      'paid_total', v_new_paid_total
    );
  end if;

  if p_idempotency_key is not null and btrim(p_idempotency_key) <> '' then
    perform app.complete_idempotency(p_arena_id, p_idempotency_key, v_response);
  end if;

  return v_response;
end;
$$;
