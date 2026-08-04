# 10 — Feature Matrix

Legend: ✔ production · △ partial · ◐ mock/hardcoded · ✖ not started

| Feature | Flutter | Web | Backend RPC | Database | Status |
|---|---|---|---|---|---|
| Email auth | ✔ | ✔ | Auth + `me` | profiles / arena_users | **Production** |
| Branch select | ✔ | ✔ | `me` | arenas / settings | **Production** |
| Device register | ✔ | ✔ | `register_device` | devices | **Production** |
| Permissions gate | △ | △ | `require_permission` | permissions / roles | **Partial** |
| Floor snapshot | ✔ | ✔ | `floor_snapshot` | stations / sessions | **Production** |
| Session start | △ | △ | `session_start` | sessions | **Partial** |
| Session pause/resume/stop | ✔ | ✔ | session_* | sessions | **Production** |
| Session extend/cancel | ✖ | ✖ | ✖ | (status enum ready) | **Not Started** |
| Unbilled queue | ✔ | ✔ | `unbilled_sessions` | sessions / orders | **Production** |
| Checkout settle | △ | △ | checkout / order_* | orders / payments | **Partial** |
| Add product line | △ | △ | `order_add_product` | order_items / stock | **Partial** |
| Discount | △ | ✖ | `order_apply_discount` | orders | **Partial** |
| Split payment | ✖ | ✖ | ✖ (single settle) | payments | **Not Started** |
| Shift open/close | ✔ | ✔ | shift_* | shifts | **Production** |
| Members CRM | ◐ lobby | ◐ | ✖ | members table only | **Mock / Not Started** |
| Membership plans | ◐ lobby | ◐ | ✖ | ✖ tables | **Not Started** |
| Wallet / coins | ◐ lobby | ◐ | ✖ | ✖ | **Not Started** |
| Inventory adjust | ◐ lobby | ◐ | ✖ | products / stock | **Mock / Not Started** |
| Inventory sell | △ | △ | via checkout | movements | **Partial** |
| Reports | ✖ | ◐ | ✖ | audit selectable | **Mock / Not Started** |
| Dashboard KPIs | ✖ | ◐ | ✖ | — | **Mock** |
| Stations admin | ✖ | ◐ | ✖ | stations | **Hardcoded UI** |
| Staff admin | ✖ | ◐ | ✖ | arena_users / roles | **Mock** |
| Settings UI | ✖ | ◐ | ✖ | arena_settings | **Mock** |
| Expenses | ✖ | ◐ | ✖ | ✖ table | **Mock / Not Started** |
| Offline sync | ✖ | ✖ | ✖ sync_pull | ✖ | **Not Started** |
| Receipt print | ✖ | ✖ | settle returns # | receipts | **Not Started** |
| Realtime | ✖ | ✖ | — | no publication | **Not Started** |
| Customer app | ✖ | — | — | — | **Not Started** |
| Super Admin | — | ✖ | provision only | no platform schema | **Not Started** |

---

## Reading guide

- **✔ across a row** ≈ safe to demo to a pilot operator for that capability
- **◐** ≈ do not trust for business decisions
- **✖ backend** ≈ do not start Flutter/Web UI claiming completion
