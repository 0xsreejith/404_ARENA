# Arena OS

## Vision

Arena OS is an operating system for gaming centres.

It replaces separate timers, notebooks, POS tools, membership sheets, stock
spreadsheets and shift calculations with one connected platform.

## Customers

- gaming cafés
- console gaming centres
- esports lounges
- VR gaming centres
- hybrid entertainment venues

## SaaS

Arena OS is multi-tenant. The **arena** is the operational tenant boundary
(D02).

404 Arena is tenant #1 and the pilot site. It is **not** the product. Nothing
specific to it — names, stations, station types, rates, games, products,
opening hours, tax settings, currency, timezone, receipt format, staff — is
ever hardcoded. All of it is tenant configuration created by `provision_arena`
(`DATABASE.md` §15).

The pilot trades in India in INR with tax-inclusive GST pricing. Every part of
that is a row in a table. A tenant in another country configures different
rows and needs no code change — that is the difference between a product and a
bespoke build.

The system must support additional independent businesses without forking the
application. That claim is proven at Milestone 10, not asserted earlier.

`organizations` exists and owns arenas, but cross-arena aggregation and
multi-location dashboards are post-MVP.

---

## Users

### Owner

Needs visibility and control.

- business setup and arena settings
- pricing and tax configuration
- staff and permissions
- products
- shift and sales reporting
- multiple locations, eventually

In the first MVP the owner uses the tablet app with owner permissions, or
Supabase Studio. **There is no web console in this repository** (D26).

### Manager

Runs daily operations.

- manage sessions, including cancel
- open and close shifts
- adjust and receive stock
- authorise discounts
- void an unsettled order
- mark a station unavailable
- view reports and the audit log

Exact permissions are configurable per arena (`PERMISSIONS.md`).

### Staff

Optimised for counter operation.

- see the floor
- start and manage sessions
- stop and bill
- take payment
- find or create a member
- sell snacks
- open a shift

---

## Core concept

The floor is the centre of the staff experience.

Staff should immediately understand which stations are:

- available
- playing
- ending soon
- in overtime
- paused
- unavailable
- stopped but not yet billed

Those states are **derived** from session timestamps and station status, never
stored (D06, `UI_SPEC.md` §3).

---

## Product principles

**Routine counter actions take as few interactions as practical.** Starting a
normal walk-in session is a few taps and no typing.

**The counter keeps working when the internet does not.** The floor stays
accurate, timers keep running, and sessions start and stop offline. Taking
money requires connectivity — the app says so plainly rather than pretending
(D15).

**The server owns money.** Bills, discounts, tax, totals, stock, and permission
decisions are computed and enforced server-side. The app displays; it does not
decide (D05).

**History does not change.** A bill computed last month stays what it was when
pricing, tax, or product configuration changes later. Sessions and order lines
carry immutable snapshots (D11, D12).

**Nothing is silently lost.** A queued action that fails reaches a human. An
audit record exists for every action that touches money, access, or state
(D22).

---

## What Arena OS is not, yet

Named so the shape of the product is clear.

Not a customer-facing booking product. Not an accounting system. Not a
tournament platform. Not a marketing tool. Not a hardware controller — Arena OS
does not lock or unlock a PC.

The MVP does one thing completely: **run one gaming centre's trading day, and
balance the drawer at the end of it.**
