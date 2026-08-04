# Arena OS — Product Surfaces

Seven shippable products. Permissions filter modules; design systems differ by surface.

---

## 1. Flutter Staff App (`mobile/`)

**Users:** Owner, Manager, Cashier, Floor Staff, Technician, Inventory Manager  
**Design:** `404 Lobby OS.dc.html` counter tablet (172 sidebar / 76 header)  
**Primary nav:** Floor · Members · Snacks · Shift · More (Reports, Settings, Tasks, Maintenance)

| Module | Screens (see SCREEN_INVENTORY) |
|---|---|
| Auth | Login PIN/email, MFA, unlock |
| Floor | Live grid/map, session sheets, time-up |
| Checkout | Bill, payments, unbilled |
| Members | Search, profile, block |
| Inventory | Stock, adjust, PO receive |
| Shift | Open/close, variance |
| Bookings | Day board (manager) |
| Tech | Maintenance, station health |
| Reports | Manager summaries |

**Offline:** banners + Sync Issues; checkout disabled offline.

---

## 2. Flutter Customer App (`mobile_customer/`)

**Users:** Members / guests  
**Design:** Consumer-friendly; arena branding colours  

| Module | Screens |
|---|---|
| Auth | Register, OTP, biometric |
| Home | Availability, promos |
| Book | Calendar, deposit pay |
| Session | Active session view, extend request |
| Wallet | Top-up, history |
| Membership | Plans, renew |
| Rewards | Points, coupons |
| Invoices | List, PDF |
| Support | Tickets |
| Profile | CRM self-serve fields |

**Cannot:** mutate floor, open shifts, adjust inventory.

---

## 3. Web Owner Dashboard (`web/`)

**Users:** Owner, Manager, Accountant  
**Design:** Lobby HTML OWNER WEB (1440, `T` tokens)  
**IA (WEBNAV):**

Dashboard · Live Floor · Stations · Sessions · Checkout Queue · Bookings · Members · Memberships · Loyalty · Wallet admin · Games · Inventory · Suppliers · Expenses · Staff · Roles · Reports · Analytics · Tournaments · Events · Marketing · Integrations · Maintenance · Audit · Settings · Branding · Branches · Devices · Notifications · Taxes · Pricing · Packages

---

## 4. Super Admin SaaS Panel (`platform/`)

**Users:** Arena OS operator  
**Modules:** Tenants · Subscriptions · Plans · Invoices · Feature Flags · Domains · White Label · Usage · Support · Impersonation · Platform Analytics · System Health

---

## 5. Backend (`supabase/`)

Migrations · RPCs · RLS · Storage buckets (member photos, logos, documents) · Edge Functions (webhooks, notifications) · pgTAP · Seed  

---

## 6. Marketing Website (`website/`)

Home · Features · Pricing · Industries · Customers · Blog · Docs link · Contact / Demo · Legal (Privacy, Terms)

---

## 7. Customer Portal (`portal/`)

Web parity with Customer App modules for desktop members.

---

## Permission → surface matrix (summary)

| Permission family | Staff | Owner Web | Customer | Super Admin |
|---|---|---|---|---|
| session.* | ✓ | ✓ | read own | — |
| payment.* | ✓ | ✓ | wallet pay | — |
| member.* | ✓ | ✓ | self | — |
| inventory.* | ✓ | ✓ | — | — |
| report.* | manager+ | ✓ | — | platform |
| arena.settings | owner | ✓ | — | — |
| platform.* | — | — | — | ✓ |
