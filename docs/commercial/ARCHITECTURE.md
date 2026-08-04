# Arena OS — Commercial System Architecture

**Extends:** `docs/ARCHITECTURE.md` (Flutter staff) — does not replace it.  
**Stack lock:** Supabase · PostgreSQL · Auth · Storage · (optional) Edge Functions · Flutter · React · Riverpod · Vite

---

## 1. Logical system context

```
┌─────────────┐  ┌──────────────┐  ┌─────────────┐  ┌──────────────┐
│ Staff App   │  │ Customer App │  │ Owner Web   │  │ Customer     │
│ Flutter     │  │ Flutter      │  │ React       │  │ Portal React │
└──────┬──────┘  └──────┬───────┘  └──────┬──────┘  └──────┬───────┘
       │                │                 │                 │
       └────────────────┴────────┬────────┴─────────────────┘
                                 │  supabase-js / supabase_flutter
                                 ▼
                    ┌────────────────────────────┐
                    │ Supabase project (per env) │
                    │ Auth · PostgREST · RPC     │
                    │ Realtime (opt) · Storage   │
                    │ Edge Functions (webhooks)  │
                    └─────────────┬──────────────┘
                                  │
              ┌───────────────────┼───────────────────┐
              ▼                   ▼                   ▼
        public.* arena      platform.* SaaS      integrations
        operational DB      tenants/billing      agents/webhooks
              │
              ▼
        ┌──────────────┐     ┌─────────────────┐
        │ Device agents│────▶│ Super Admin Web │
        │ (PC/PS5) INT │     │ platform/       │
        └──────────────┘     └─────────────────┘
```

**Marketing website** is static/SSR; talks only to lead-capture Edge Function — no arena data.

---

## 2. Tenancy model

| Layer | Meaning |
|---|---|
| **Organization** | Franchise / company grouping |
| **Arena** | Operational tenant (D02) — RLS boundary |
| **Platform tenant** | SaaS customer record linking org + subscription |

Staff apps never see `platform.*` tables. Super Admin never uses arena staff JWT for money writes.

---

## 3. Write path (unchanged doctrine)

```
UI → Controller (Riverpod) → Repository → RPC (SECURITY DEFINER)
                                      → app.require_permission
                                      → app.current_actor_id()
                                      → domain tables + audit
```

Clients: **zero** INSERT/UPDATE/DELETE privileges on operational tables.

---

## 4. Read path

| Data | Pattern |
|---|---|
| Floor catalogue | SELECT under RLS **or** `floor_snapshot` |
| Members / CRM | RPC only (D19) |
| Reports | RPC aggregates (no heavy client joins) |
| Platform admin | platform RPCs + service role only on server |

---

## 5. Surface architectures

### 5.1 Flutter Staff (`mobile/`)

- Continues `ARCHITECTURE.md`: `app/`, `core/`, `features/`, Riverpod 3  
- Converge Lobby shell (D39)  
- Features map 1:1 to PRD modules as packages under `features/`  
- Offline: Drift outbox for allowed ops only  

### 5.2 Flutter Customer (`mobile_customer/`)

- Separate app id; same Supabase project; **member** auth role  
- Features: auth, book, wallet, membership, invoices, rewards  
- No floor mutation RPCs granted to customer role  

### 5.3 Owner Web (`web/`)

- React + Vite; URL router; design tokens from Lobby OWNER WEB  
- Modules as route groups: `/floor`, `/members`, `/inventory`, `/reports`, …  
- Same RPCs as staff where permissions allow  

### 5.4 Super Admin (`platform/`)

- Separate deploy; platform schema; break-glass audit  
- No composite arena FKs for SaaS billing tables  

### 5.5 Portal (`portal/`)

- React; customer JWT; subset of customer RPCs  

### 5.6 Website (`website/`)

- Marketing only  

---

## 6. Integration architecture

```
Edge Function  ←webhooks─  Stripe/Razorpay/WhatsApp
      │
      ▼ idempotent ledger RPCs
 arena payments / wallet / notifications_outbox

Device Agent (optional native service on PC)
      │ heartbeat + commands
      ▼
 station_assets / station_telemetry tables
```

---

## 7. Realtime strategy

| Phase | Approach |
|---|---|
| P0 / CORE | 10s poll (D23) |
| COMM | Supabase Realtime on floor channels per arena; repos stay Stream-shaped |

---

## 8. Folder structure (target monorepo)

```
arena-os/
  docs/                 # contract + commercial/
  supabase/             # migrations, tests, seed
  mobile/               # staff Flutter
  mobile_customer/      # customer Flutter
  web/                  # owner dashboard
  portal/               # customer web
  platform/             # super admin
  website/              # marketing
  agents/               # optional device agent
  scripts/              # db.sh, ci.sh
```

---

## 9. Environment topology (D34)

Three Supabase projects: development · staging · production.  
Platform SaaS billing may use the same projects with `platform` schema **or** a dedicated platform project in Enterprise — decide in D41 (see DECISIONS).

---

## 10. AI architecture (extension only)

```
insights_jobs → worker → model provider → insights_results (arena_id)
RPC insights_get → UI
If flag off → RPC returns not_implemented
```

No client-side “AI” random text.
