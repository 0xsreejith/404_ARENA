# Arena OS — Business Requirements Document (BRD)

**Version:** 1.0 · Commercial  
**Owner:** Product + Architecture  
**Audience:** Investors, operators, engineering, design, support

---

## 1. Executive summary

Arena OS is a **multi-tenant commercial operating system** for gaming and entertainment venues. It unifies floor operations, POS, memberships, CRM, inventory, staff, finance, bookings, tournaments, marketing, and franchise/SaaS control into one platform sold worldwide.

**404 Arena** is the pilot customer only. The product is sold as white-label-capable SaaS to any gaming centre, lounge, esports arena, VR centre, LAN café, console café, board-game café, or multi-branch franchise.

---

## 2. Problem

Venue operators today stitch together:

- Timers / station sheets  
- Notebooks for sessions  
- Separate POS  
- Spreadsheet stock  
- WhatsApp for bookings  
- Manual membership cards  
- Cash drawer guesswork  

This causes revenue leakage, tax risk, staff fraud exposure, poor retention, and inability to franchise.

---

## 3. Solution

One arena-scoped tenant OS with:

| Capability | Business value |
|---|---|
| Live floor + sessions | Capture every billable minute |
| Server-authoritative billing | Correct tax, receipts, audits |
| CRM + loyalty + wallet | Retention and LTV |
| Inventory + POS | Snack/controller margin |
| Shift + finance | Drawer balances; GST-ready |
| Bookings + events + tournaments | Utilisation + new revenue |
| Multi-branch + SaaS | Franchise and platform scale |
| Hardware integrations | PC/PS5 ops efficiency |
| AI (real, optional) | Forecasts — never fake insights |

---

## 4. Target market

### Primary

Gaming cafés · PS5/console centres · Esports lounges · LAN centres · VR centres · Hybrid entertainment venues

### Secondary

Board-game cafés · Franchise chains · Soft-play + gaming hybrids · University gaming labs (B2B)

### Buyer personas

| Persona | Job to be done |
|---|---|
| **Owner** | Profit, tax, multi-branch visibility, brand |
| **Manager** | Run a shift, resolve exceptions, staff |
| **Cashier / Floor staff** | Fast walk-in → session → pay |
| **Technician** | Station health, maintenance |
| **Inventory manager** | Stock accuracy |
| **Accountant** | Ledgers, GST, exports |
| **Member** | Book, wallet, membership, rewards |
| **Platform operator** | Tenants, billing, support |

---

## 5. Products & revenue model

### Products

1. Flutter Staff App  
2. Flutter Customer App  
3. Web Owner Dashboard  
4. Super Admin SaaS Panel  
5. Supabase Backend  
6. Marketing Website  
7. Customer Web Portal  

### SaaS monetization (platform)

| Plan | Includes (illustrative) |
|---|---|
| Starter | 1 arena, core floor+POS, limited stations |
| Growth | Multi-branch, CRM, bookings, inventory |
| Enterprise | White-label, custom domain, SSO, SLA, AI packs |
| Add-ons | Hardware agents, WhatsApp, advanced analytics |

Tenant billing, invoices, feature flags, and usage metering live in the **platform** schema — never mixed into arena operational money tables without clear separation.

---

## 6. Business rules (non-negotiable)

1. **Arena** is the operational tenant boundary; organizations group arenas.  
2. **Server owns money** — no client-computed stored totals.  
3. **Append-only** payments, inventory movements, wallet ledgers, loyalty ledgers, audit.  
4. **Composite tenant FKs** on all tenant data.  
5. **RBAC by permission code**, not role name.  
6. **PII minimization** — members RPC-only; no bulk sync of full CRM to every device.  
7. **Configurable jurisdiction** — currency, tax, receipt series, dial code as data.  
8. **Offline:** only explicitly allowed ops (start/stop sessions); checkout never offline.  
9. **No fake AI** — AI modules ship models/APIs or stay “not enabled”.  
10. **White-label** via branding settings + custom domain — not forks per customer.

---

## 7. Success metrics

| Metric | Target (12 months post commercial GA) |
|---|---|
| Paying tenants | Growth KPI (commercial) |
| Pilot trading days without notebook | 100% at 404 after M7 |
| Drawer variance unexplained | → 0 with notes |
| Session → settle conversion | Tracked |
| Member return rate | Tracked |
| Support tickets / tenant / month | Declining |
| Uptime | 99.9% API |
| Restore drill | Documented annually |

---

## 8. Compliance & risk

| Area | Approach |
|---|---|
| Tax (e.g. India GST) | Component rates as data; place-of-supply later |
| PCI | Prefer hosted payment providers; no raw PAN storage |
| Privacy | Consent flags; retention policies; export/delete |
| Labour | Attendance optional module; local labour law is tenant responsibility |
| Backups | PITR + rehearsed restore (D37) |

---

## 9. Out of scope for *platform* (but documented as integrations)

- Building Steam/Epic/PlayStation themselves  
- Running tournaments as a league organizer brand  
- Hardware manufacture  

Arena OS **integrates** and **orchestrates**.

---

## 10. Dependencies

Existing Arena OS foundations (M1 schema, RLS, RPC pattern, Flutter/React shells, Lobby design HTML) are the substrate. Commercial modules are **additive migrations and new surfaces**, not a rewrite.
