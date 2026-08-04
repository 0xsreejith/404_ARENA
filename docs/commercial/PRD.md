# Arena OS — Product Requirements Document (PRD)

**Version:** 1.0 · Commercial  
**Rule:** Every module listed by Product is specified here. None omitted.  
**Implementation:** Wave-ordered in `ROADMAP_COMMERCIAL.md`. Core trading path still precedes franchise/AI.

**Legend — Status vs current codebase**

| Tag | Meaning |
|---|---|
| **NOW** | Exists (schema and/or RPC and/or UI partial) |
| **CORE** | Required for trading-day / M7–M10 path |
| **COMM** | Commercial catalogue — full SaaS |
| **INT** | Integration-dependent |
| **AI** | Extension point; ship only with real backend |

---

## 0. Cross-cutting requirements

| ID | Requirement |
|---|---|
| X1 | Multi-tenant isolation by `arena_id` + composite FKs |
| X2 | Multi-branch: user may belong to many arenas; switcher mandatory |
| X3 | All mutations via SECURITY DEFINER RPCs + permission codes |
| X4 | Audit every stateful/financial action |
| X5 | i18n-ready strings; locale in settings |
| X6 | Currency ISO 4217 per arena; money as numeric / minor units |
| X7 | Branding: logo, colours, brand name from `arena_settings` |
| X8 | Feature flags per tenant (platform) |
| X9 | Accessibility: WCAG 2.1 AA target on web; large touch targets on staff |
| X10 | Design parity: counter = Lobby HTML; Owner Web = HTML W* theme |

---

## 1. Authentication — COMM + CORE

| Feature | Req | Status |
|---|---|---|
| Email/password login | Staff + owner + customer | **NOW** (staff) |
| Logout | All surfaces | **NOW** |
| Forgot / reset password | Supabase Auth recovery | **COMM** |
| MFA (TOTP) | Opt-in per user / enforced for owner | **COMM** |
| Device trust | Register device; trust list; revoke | **NOW** partial (`devices`) |
| Session management | List/revoke refresh sessions | **COMM** |
| Staff PIN | Fast unlock on shared tablet (D04 deferred → COMM) | **COMM** |
| QR login | Short-lived QR challenge | **COMM** |
| Biometric | Platform biometrics wrapping secure session | **COMM** |
| Customer OTP / phone login | E.164 + OTP | **COMM** |

**Acceptance:** Stolen device: revoke trust; MFA for owners on commercial plans.

---

## 2. Role management — CORE + COMM

### System role templates (seeded, customizable)

Owner · Manager · Cashier · Staff · Floor Staff · Technician · Inventory Manager · Accountant · Super Admin (platform only)

### Features

| Feature | Req |
|---|---|
| Custom roles | Arena-scoped roles + permission matrix |
| Permission matrix UI | Toggle 33+ codes; expand catalogue as modules land |
| Role clone | Copy role permissions |
| Staff invite | Email invite → `arena_users` |
| Soft-disable staff | `arena_users.active = false` |

**Note:** Authorize by **permission code**, never role name (existing rule).

---

## 3. Gaming floor — CORE + COMM

| Feature | Req | Status |
|---|---|---|
| Live Floor | Station cards, timers, derived states | **NOW** |
| Live Map | Visual layout of zones/stations | **COMM** |
| Zones | CRUD, sort | **NOW** schema |
| Floor layout | Positions x/y, drag-drop editor (Owner Web) | **COMM** |
| Station status (ops) | active / maintenance / inactive | **NOW** |
| Presentation states | idle, live, paused, ending, overtime, reserved, cleaning, offline, broken | **NOW** partial + **COMM** extend |
| Reserved | From bookings | **COMM** |
| Cleaning | Post-session cooldown state | **COMM** |
| Offline / Online | Device agent heartbeat | **COMM**/INT |
| Broken | Fault flag + ticket link | **COMM** |
| Emergency lock | Freeze starts arena-wide | **COMM** |

---

## 4. Station types — CORE (data) + COMM (catalogue UX)

Configurable `station_types` (already normalised — D27). Required catalogue seeds (tenant-editable):

Gaming PC · PS5 · PS4 · Xbox · Nintendo Switch · VR · Pool · Snooker · Table Tennis · Arcade · Racing Simulator · Private Room · VIP Room · Console Room · Hourly Booth · Seat · (future: any)

**No type hardcoded in app logic.**

---

## 5. Station management — CORE + COMM + INT

| Feature | Wave |
|---|---|
| Create / Update / Soft-delete / Clone / Bulk edit | COMM |
| Maintenance mode + reason | CORE (**NOW** RPC) |
| Restart / Shutdown / Wake-on-LAN | INT (agent) |
| Hardware monitoring (temp, perf, network, health) | INT |
| Controllers / displays as child assets | COMM |

---

## 6. Game library — COMM + INT

Games · Genres · Installed games per station · Versions · Launchers:

Steam · Epic · Battle.net · Riot · EA · Ubisoft · Rockstar · Game Pass · PlayStation · Xbox · Nintendo

Station↔game bindings; launch commands; license notes.

---

## 7. Session management — CORE + COMM

| Feature | Status |
|---|---|
| Start / Pause / Resume / Stop | **NOW** |
| Extend / Cancel | CORE (RPCs pending) |
| Transfer / Move station | COMM |
| Merge / Split sessions | COMM |
| Upgrade package | COMM |
| Emergency stop (manager) | COMM |
| Pricing snapshot at start | **NOW** |

---

## 8. Bookings — COMM

Advance · Reservations · Recurring · Online · Walk-in · QR · VIP · Tournament · Waitlist · Calendar

Rules: deposit optional; no-show tracking; conflict with live sessions; permission gates.

---

## 9. Membership system — COMM

Tiers: Guest · Regular · Silver · Gold · Platinum · Diamond · VIP · Corporate · Student  

Plans: Monthly · Yearly · Family · Unlimited · Expiry · Renewal · Auto-renew · Discounts · Exclusive pricing · Free hours · Priority booking · Reward multipliers

Tables: `membership_plans`, `member_memberships` (previously deferred D28 — opened by D40/D28a).

---

## 10. Customer app — COMM (new Flutter surface)

Registration · Wallet · Membership · Bookings · Invoices · Rewards · Referral · Notifications · Purchase packages · Extend sessions · Live availability · Rate experience · Support chat/ticket

---

## 11. CRM — CORE thin → COMM full

### P0 / CORE fields (exist or near-term)

Name · Phone (E.164) · DOB · Notes · Blocked · Visits via sessions

### Full commercial profile

Photo · Documents · Emergency contact · Address · Email · WhatsApp · Gender · Visit history · Invoices · Membership · Wallet · Packages · Rewards · Achievements · Favourite games/stations · Birthday · Anniversary · Marketing consent · Joined / Member since · Stats (hours, spend, LTV, frequency) · Active session · Timeline

**Privacy:** No client SELECT on `members`; RPC search with limits (D19).

---

## 12. Loyalty — COMM

Points ledger · Levels · Badges · Achievements · Daily login · Referral · Coupons · Gift cards · Promo codes · Scratch cards · Lucky draw  

All balances from **append-only ledgers**.

---

## 13. Wallet — COMM

Top-up · Refund · Transfer · Bonus · Cashback · Credit · Debit · History  

Wallet ≠ cash drawer. Wallet movements are append-only; settlements may pay via `method = wallet`.

---

## 14. Packages / pricing — CORE + COMM

Hourly (open_time) · Fixed duration · Daily/Weekly/Monthly · Unlimited · Night · Student · Weekend · Festival · Combo · Happy hours · Rules engine (time-of-day, member tier)

P0: open_time + fixed_duration only (D10). Commercial unlocks rules engine.

---

## 15. PS5 management — COMM + INT

Installed games · Controller assignment · Battery · Controller inventory · Disc tracking · Licenses · Console health · Firmware · DualSense pairing  

Requires device agent or manual ops UI where agent absent.

---

## 16. PC management — COMM + INT

Installed games · Windows · GPU/CPU/RAM/Storage · Temperature · Steam login profile · Remote restart · WoL  

---

## 17. Inventory — CORE + COMM

Snacks · Drinks · Accessories · Controllers · Headsets · Chargers · HDMI · Cables · Merch  

Stock · Suppliers · Purchase orders · Barcode/QR · Categories · Bundles · Transfers (inter-branch) · Adjustments · Low stock · Counter sales  

P0: products + movements + stock (**schema NOW**; RPCs partial).

---

## 18. Point of sale — CORE + COMM

Cart · Discount · Coupons · Split payment · Cash · Card · UPI · Wallet · Gift card · Refund · Exchange · Invoice · Tax/GST · Tips  

Server totals only. Checkout online-only (D15).

---

## 19. Finance — COMM (+ CORE shift cash)

Income · Expense · Profit views · Daily closing · Cash drawer · Bank deposits · Ledger · GST reports · Tax reports · Audit logs  

P0: shift expected/counted/variance. Commercial: full ledger + expenses.

---

## 20. Shift management — CORE + COMM

Open · Close · Cash count · Variance · Notes · Attendance link · Clock in/out · Breaks  

One open shift per arena (D30) unless amended for multi-drawer COMM flag.

---

## 21. Staff HR — COMM

Attendance · Leaves · Salary hooks · Commission · Performance · Leaderboard · Tasks  

---

## 22. Tournaments — COMM

Create · Registration · Brackets · Fixtures · Scores · Leaderboard · Winners · Prizes · Streaming links  

---

## 23. Events — COMM

Birthdays · Private · Corporate · LAN · Watch parties · Resource holds (rooms/stations)

---

## 24. Notifications — COMM + INT

Push (FCM — post-MVP historically; now COMM) · SMS · Email · WhatsApp · In-app  

Triggers: booking reminder · membership expiry · offers · shift alerts · low stock  

---

## 25. Reports & analytics — CORE + COMM

Sales · Sessions · Revenue · Station usage · Peak hours · Member growth · Inventory · Staff · Tax · P&L · Dashboard  

Exports: CSV / PDF. Owner Web primary; manager tablet secondary.

---

## 26. AI — AI

Revenue forecast · Peak prediction · Demand · Customer insights · Inventory forecast · Chat assistant  

**Requirement:** Real model pipeline or provider integration. Feature flag off by default. Never fabricate numbers.

---

## 27. Multi-branch — COMM

Unlimited arenas per org · Inventory transfer · Member transfer / shared org member directory (opt-in) · Central dashboard  

---

## 28. SaaS platform — COMM (Super Admin)

Tenants · Subscriptions · Plans · Billing · Invoices · Feature flags · White label · Custom domain · Usage metering · Support tools · Impersonation (audited)

---

## 29. Marketing — COMM

Coupons · Referral · Campaigns · Email/WhatsApp/Push · Birthday campaigns  

Consent-gated (CRM marketing consent).

---

## 30. Security — CORE + COMM

RBAC · Audit logs · Encryption in transit · Backups/PITR · Rate limiting · Fraud signals · Device trust · RLS · No service_role in clients  

---

## 31. Settings — CORE + COMM

Business · Branding · Themes · Receipt · Taxes · Currency · Language · Printer · Backup status · Business hours · Dial code  

---

## 32. Integrations — INT

Stripe · Razorpay · PhonePe · Google Pay · WhatsApp · Firebase · Steam · PlayStation · Xbox · Discord · OBS · Telegram  

Each integration: credentials in secrets store; webhook idempotency; disable without breaking core POS cash/UPI manual entry.

---

## 33. Website & portal — COMM

**Website:** Marketing, pricing, demo request, docs links.  
**Customer portal:** Browser twin of customer app (bookings, wallet, invoices).

---

## Non-functional requirements

| NFR | Target |
|---|---|
| Floor poll / realtime | ≤10s poll P0; Realtime optional COMM |
| 40–80 stations UI | Smooth 60fps timers (leaf widgets) |
| API p95 | <300ms for floor_snapshot typical |
| RPO/RTO | PITR; restore drill documented |
| Locale | en base; +hi, +ar, +id roadmap |

---

## Traceability

Every PRD module maps to:

- Tables in `DATABASE_SCHEMA.md`  
- RPCs in `API_SURFACE.md`  
- Screens in `SCREEN_INVENTORY.md`  
- Wave in `ROADMAP_COMMERCIAL.md`
