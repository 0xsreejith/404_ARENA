# Arena OS — Commercial Product Suite

**Status:** Binding product expansion for a worldwide SaaS gaming-centre OS  
**Date:** 2026-08-04  
**Stack (unchanged):** Supabase PostgreSQL · SECURITY DEFINER RPCs · Flutter · React · Riverpod  
**Visual SoT:** `404 Lobby OS.dc.html`  
**Technical SoT:** `docs/DECISIONS.md` (D01–D37 + commercial amendments D40+)  
**Pilot:** 404 Arena = tenant #1 only — never hardcoded

This folder is the **commercial product bible**. It does **not** replace M1–M10 foundations; it defines the complete sellable platform built **on top of** them.

---

## Deliverables index

| # | Document | Contents |
|---|---|---|
| 1 | [BRD.md](./BRD.md) | Business Requirements Document |
| 2 | [PRD.md](./PRD.md) | Product Requirements — **every module**, none omitted |
| 3 | [ARCHITECTURE.md](./ARCHITECTURE.md) | System + surface architecture |
| 4 | [DATABASE_SCHEMA.md](./DATABASE_SCHEMA.md) | Target schema (P0 + commercial expansions) |
| 5 | [API_SURFACE.md](./API_SURFACE.md) | RPC / API catalogue by domain |
| 6 | [SURFACES.md](./SURFACES.md) | Staff app, Customer app, Owner Web, Super Admin, Website, Portal |
| 7 | [DESIGN_SYSTEM.md](./DESIGN_SYSTEM.md) | Tokens, components, parity rules |
| 8 | [USER_FLOWS.md](./USER_FLOWS.md) | End-to-end flows |
| 9 | [SCREEN_INVENTORY.md](./SCREEN_INVENTORY.md) | Figma-level screen catalogue + wireframe specs |
| 10 | [ROADMAP_COMMERCIAL.md](./ROADMAP_COMMERCIAL.md) | Wave-based developer roadmap to production |
| 11 | [TESTING_SECURITY_DEPLOY.md](./TESTING_SECURITY_DEPLOY.md) | Testing, security, CI/CD, monitoring, go-live |

**Related living docs (existing):** `../PRODUCT.md`, `../MVP.md`, `../DECISIONS.md`, `../DATABASE.md`, `../API.md`, `../UI_SPEC.md`, `../ROADMAP.md`, `../../IMPLEMENTATION_PLAN.md`, `../../PROJECT_UNDERSTANDING.md`

---

## Products (seven surfaces)

| Product | Repo path (target) | Primary users |
|---|---|---|
| **Flutter Staff App** | `mobile/` | Owner, Manager, Cashier, Floor Staff, Technician |
| **Flutter Customer App** | `mobile_customer/` (new) | Members / walk-in guests |
| **Web Owner Dashboard** | `web/` | Owner, Manager, Accountant |
| **Super Admin SaaS Panel** | `platform/` (new) | Arena OS operator |
| **Backend** | `supabase/` | All |
| **Marketing Website** | `website/` (new) | Prospects |
| **Customer Portal (web)** | `portal/` (new) | Members (browser) |

---

## Quality bar

Comparable to: Toast / Square / Lightspeed / Mindbody / Shopify POS + CRM depth, specialized for gaming venues.

Every feature is:

1. Documented here  
2. Schema-ready (additive migrations)  
3. RPC-secured  
4. Multi-tenant / multi-branch  
5. Tested (pgTAP + client)  
6. UI-parity with design system  
7. Configurable per tenant — **no 404 hardcoding**

---

## Relationship to pilot MVP

| Layer | Role |
|---|---|
| M0–M10 / Epic 3C…13 | **Trading-day core** — still ship first |
| Commercial Waves W1–W8 | Full SaaS catalogue in this bible |
| Pilot go-live | Still gated by M7 + PITR (D37) |

Commercial scope is **authorized** by decision **D40** (see `DECISIONS.md`). Implementation order remains wave-based — documenting everything does not mean building everything in parallel.
