# 16 — Changelog (Epic Summary)

Synthesized from migrations, `IMPLEMENTATION_PLAN.md`, README, and ROADMAP progress notes. Not a git log dump.

---

## Epic / milestone timeline

| Epic | When (docs) | Delivered |
|---|---|---|
| **M0** | Foundations | Flutter project, Money, AppFailure, theme, flavours, CI, pgTAP harness, three-env model |
| **M1** | Schema security | 28 tables, RLS, algorithms, permission catalogue, `provision_arena`, seed, pgTAP suite |
| **Epic 1** | Auth backend | Branding columns, `me()`, `register_device` |
| **Epic 2** | Floor ops | `floor_snapshot`, `session_start/pause/resume/stop`, `station_set_status` |
| **Epic 3** | Checkout | Initial checkout/order RPCs |
| **Epic 3C** | 2026-08-04 ✅ | Checkout integrity — M1 algorithms, receipts, no hardcoded `1.18`; test `16_*` |
| **Epic 4** | 2026-08-04 ✅ | Auth context M2 — Flutter router/permissions/stale; Web auth shell; `devices.platform` web/desktop; test `17_*` |
| **Epic 5** | 2026-08-04 ✅ | Floor billing — unbilled, preview money strings, checkout wire-up; test `18_*` |
| **Epic 6** | 2026-08-04 ✅ | Shift cash — shift_current/open/summary/close; Flutter `/shift`; Web ShiftPanel; test `19_*` |
| **Epic 7** | 2026-08-04 🟡 | Phase 1 Lobby chrome shell; Phase 2 live station cards + `seat_capacity`; Owner Web light W1–W13 shells |

---

## Key files introduced / heavily changed (by area)

| Area | Paths |
|---|---|
| Migrations | `supabase/migrations/20260730*` → `20260804190000_*` |
| pgTAP | `supabase/tests/00_*` … `19_epic6_*` |
| Flutter auth/tenant | `features/auth`, `features/tenant`, `app/router.dart` |
| Flutter floor/checkout/shift | `features/floor`, `checkout`, `shift` |
| Flutter lobby demo | `features/lobby_ui/**`, `main_lobby.dart` |
| Web live ops | `services/{floor,shift,checkout,device}.ts`, `LiveFloorGrid`, `CheckoutPanel`, `ShiftPanel` |
| Web owner shell | `OwnerShell`, `owner.css`, `OwnerPages.tsx`, `ownerFixtures.ts` |

---

## Current milestone

**Epics 3C–6 complete. Epic 7 in progress (Phases 1–2 shipped).**  
Formal ROADMAP **M7 MVP exit not complete**.

---

## Workspace-adjacent artifacts (outside `arena-os/` git product)

| File | Role |
|---|---|
| `404 Lobby OS.dc.html` | Visual source of truth for Lobby UI |
| `IMPLEMENTATION_PLAN.md` | Epic plan |
| `PROJECT_UNDERSTANDING.md` | Older snapshot — partially superseded |
| `UI_PARITY_AUDIT.md` / `OWNER_WEB_PARITY_AUDIT.md` | Parity trackers |

---

## Not yet changelogged as done

Epics 8–13 · OW2–OW9 live data · SA* · CRM* · INV/STN/RPT/EXP expansion · AI0
