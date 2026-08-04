# Permissions

Authorisation is by **permission code**, never by role name. Roles are
arena-scoped collections of permission codes (`DATABASE.md` §3).

The backend enforces every permission. Hiding a Flutter control is not
authorisation (`SECURITY.md` §5).

---

## 1. P0 permission catalogue

This is the complete set seeded in P0. A code not listed here does not exist
yet.

### Sessions

| Code | Grants |
|---|---|
| `session.view` | See the floor and session details |
| `session.start` | Start a session |
| `session.pause` | Pause a running session |
| `session.resume` | Resume a paused session |
| `session.extend` | Add a package block to a fixed-duration session |
| `session.stop` | Stop a session and open its checkout |
| `session.cancel` | Cancel a session without billing; also discard a failed offline operation (`OFFLINE.md` §9) |

### Stations

| Code | Grants |
|---|---|
| `station.view` | See stations |
| `station.update` | Edit station name, zone, type, capacity |
| `station.maintenance` | Mark a station `maintenance` or `inactive` |

### Members

| Code | Grants |
|---|---|
| `member.view` | Search and view members |
| `member.create` | Create a member |
| `member.update` | Edit member details |
| `member.block` | Block or unblock a member |

### Products and inventory

| Code | Grants |
|---|---|
| `product.view` | See products and prices |
| `product.manage` | Create and edit products |
| `inventory.view` | See current stock and movements |
| `inventory.sell` | Add products to an order; open a counter sale |
| `inventory.adjust` | Wastage, staff use, breakage, correction |
| `inventory.receive` | Restock and opening stock |

### Checkout and money

| Code | Grants |
|---|---|
| `payment.create` | Settle an order and record payment |
| `payment.view` | See payments and order history |
| `discount.apply` | Apply an order discount. **Holding this code is the authorisation** (D14) |
| `order.void` | Void an unsettled order |

### Shift

| Code | Grants |
|---|---|
| `shift.view` | See the current shift and its summary |
| `shift.open` | Open a shift |
| `shift.close` | Close a shift and record counted cash |

### Reporting

| Code | Grants |
|---|---|
| `report.view` | Shift summaries and the audit log, including session timelines |

### Administration

| Code | Grants |
|---|---|
| `arena.settings` | Arena settings, zones, station types, stations, games |
| `pricing.manage` | Billing plans, tax rates and their components, tax defaults, receipt numbering settings, tax-inclusive mode |
| `staff.view` | See who works here |
| `staff.manage` | Invite, deactivate, and assign roles to staff |
| `permissions.manage` | Edit roles and their permission sets |

**33 codes.**

---

## 2. Seeded roles

`provision_arena` creates three system roles per arena (`DATABASE.md` §15).
They are starting points — a tenant may edit them or add roles.

### `staff`

```
session.view  session.start  session.pause  session.resume
session.extend  session.stop
station.view
member.view  member.create
product.view  inventory.view  inventory.sell
shift.view  shift.open
payment.create  payment.view
```

### `manager`

Everything in `staff`, plus:

```
session.cancel
station.update  station.maintenance
member.update  member.block
product.manage  inventory.adjust  inventory.receive
shift.close
discount.apply  order.void
report.view  staff.view
```

### `owner`

Every code in the catalogue.

---

## 3. Rules

- A user holds **one role per arena** in P0. No per-user overrides.
- `permissions.manage` cannot be removed from the last holder in an arena
  (`SECURITY.md` §7).
- System roles (`is_system = true`) cannot be deleted; their permission sets can
  be edited.
- Permission checks run server-side inside every mutating RPC via
  `app.require_permission()`.
- The client caches its own permission set with a 24-hour TTL. Cached
  permissions decide what the UI **offers**; the server decides what
  **happens** (D18).
- Navigation and controls are derived from permissions. A user without
  `member.view` must not see a Members tab (audit finding C16).
- Every change to a role or a user's role writes an audit record.

---

## 4. Post-MVP codes

Reserved names, deliberately **not** seeded in P0, so they are not accidentally
introduced with different spellings later:

```
membership.view      membership.sell      membership.renew
wallet.view          wallet.adjust        wallet.redeem
payment.refund       discount.override
expense.create       expense.view         expense.manage
maintenance.view     maintenance.create   maintenance.update
asset.view           asset.update
reservation.view     reservation.manage
```
