# Arena OS — Commercial Developer Roadmap

**Principle:** Document everything now; **implement in waves**. Core trading integrity before franchise chrome.  
**Continues:** `docs/ROADMAP.md` M0–M10 + `IMPLEMENTATION_PLAN.md` Epics.  
**Does not** replace Epic 4 next (Auth M2) — commercial waves absorb and extend after CORE.

---

## Wave overview

| Wave | Name | Outcome |
|---|---|---|
| **W0** | Foundations | M0–M1 + Epic1–3C done |
| **W1** | Trading core | M2–M9 staff path: auth, floor UI parity, checkout UX, shift, members P0, inventory P0, offline |
| **W2** | Owner Web CORE | D26a: dashboard, floor, stations, pricing, tax, staff, settings, reports basic |
| **W3** | CRM & POS depth | Full CRM fields, refunds, expenses, cash movements, tips, coupons — **CRM member spine shipped 2026-08-05** (profiles/tags/notes/stats/timeline); POS extras still open |
| **W4** | Memberships · Wallet · Loyalty | D28a tables + customer entitlements — **shipped 2026-08-05** (plans, wallets, loyalty ledgers, settle hooks) |
| **W5** | Bookings · Events · Tournaments | Calendar utilisation |
| **W6** | Customer App + Portal + Website | Member self-serve + acquisition site |
| **W7** | Hardware agents · Game library · PS5/PC ops | INT |
| **W8** | SaaS Super Admin · White-label · Flags | Sellable multi-tenant platform desk |
| **W9** | Marketing automation · Omnichannel notify | Growth |
| **W10** | AI packs | Real models only |
| **W11** | Hardening | Security, perf, compliance, globalisation |

---

## Mapping PRD modules → waves

| PRD module | Wave |
|---|---|
| Auth (email) | W1 |
| Auth PIN/MFA/QR/biometric | W1–W2 |
| Roles matrix UI | W2 |
| Floor live | W1 |
| Floor map / layout | W2–W3 |
| Station types catalogue UX | W2 |
| Station CRUD / bulk | W2 |
| Hardware monitor / WoL | W7 |
| Game library | W7 |
| Sessions complete | W1 |
| Transfer/merge/split | W3 |
| Bookings | W5 |
| Memberships | W4 |
| Customer app | W6 |
| CRM full | W3–W4 |
| Loyalty / wallet | W4 |
| Packages advanced / happy hour | W3 |
| PS5 / PC mgmt | W7 |
| Inventory advanced | W3 |
| POS full | W1–W3 |
| Finance ledger | W3 |
| Shift | W1 |
| Staff HR | W5 |
| Tournaments / events | W5 |
| Notifications | W6–W9 |
| Reports | W2+ |
| AI | W10 |
| Multi-branch | W2–W3 |
| SaaS | W8 |
| Marketing | W9 |
| Security hardening | continuous + W11 |
| Settings | W1–W2 |
| Integrations payments | W3–W6 |
| Website / portal | W6 |

---

## Near-term execution (from IMPLEMENTATION_PLAN)

1. **Epic 4** — Auth context / M2 ✅ complete  
2. **Epic 5** — Checkout UI wire-up ✅ complete  
3. **Epic 6** — Shift RPCs ✅ complete  
4. **Epic 7** — Lobby shell convergence ← in progress (Phase 1 chrome ✅)  
5. Epics 8–13 — sync, sessions, members, inventory, offline, tenant #2  
6. Then enter **W2** Owner Web systematically  

---

## Definition of Done (commercial module)

Same as IMPLEMENTATION_PLAN §5, plus:

- Screen IDs implemented or explicitly deferred with ticket  
- Feature flag if COMM-only  
- Customer + Owner surfaces updated when module is member-facing  
- No 404/INR/GST literals in code  

---

## Team topology (suggested)

| Stream | Focus |
|---|---|
| Core Ops | Floor, sessions, checkout, shift |
| Commerce | CRM, wallet, memberships, bookings |
| Platform | Super Admin, flags, billing |
| Client UX | Lobby parity, Owner Web, customer apps |
| Integrations | Payments, WhatsApp, agents |
