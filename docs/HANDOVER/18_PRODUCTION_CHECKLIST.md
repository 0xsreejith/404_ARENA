# 18 — Production Checklist

Everything required before a **real customer / paying tenant** launch.  
Status reflects **repository evidence only**.

Legend: ✅ ready · 🟡 partial · ❌ missing

---

## Authentication

| Item | Status |
|---|---|
| Email/password Auth | ✅ |
| `me` + arena membership | ✅ |
| Permission enforcement server-side | ✅ |
| Device registration | ✅ |
| MFA / SSO | ❌ |
| Production password/seed hygiene | 🟡 (local seed empty password by default) |
| Session stale gate persisted | 🟡 |

---

## Floor

| Item | Status |
|---|---|
| Live floor snapshot | ✅ |
| Session start/pause/resume/stop | 🟡 (start UX incomplete) |
| Extend/cancel | ❌ |
| Maintenance status UX | 🟡 |
| 40-station performance proven | ❌ |
| Offline floor cache | ❌ |

---

## Billing

| Item | Status |
|---|---|
| Server play charge + tax algorithms | ✅ |
| Checkout preview/settle | 🟡 |
| Open shift required for settle | ✅ |
| Split tender | ❌ |
| Void unsettled | 🟡 |
| Receipt number series | ✅ |
| Receipt print/email | ❌ |
| Refunds | ❌ (post-MVP) |

---

## Shift

| Item | Status |
|---|---|
| Open / summary / close / variance | ✅ |
| One open shift constraint | ✅ |
| Cash movements / payouts | ❌ |

---

## Inventory

| Item | Status |
|---|---|
| Schema + stock materialisation | ✅ |
| Sell via order | 🟡 |
| Receive / adjust RPC + UI | ❌ |
| Low stock real alerts | ❌ |

---

## Membership

| Item | Status |
|---|---|
| Member records via RPC | ❌ |
| Memberships / wallet | ❌ (deferred) |

---

## Reports

| Item | Status |
|---|---|
| Real aggregates | ❌ |
| Fixture dashboards removed | ❌ |
| Audit viewer | ❌ |
| Export | ❌ |

---

## Printing

| Item | Status |
|---|---|
| Thermal / PDF receipt | ❌ |

---

## Backup / monitoring / analytics

| Item | Status |
|---|---|
| PITR on production | ❌ (required; not evidenced) |
| Restore rehearsal | ❌ |
| App error monitoring (Sentry etc.) | ❌ |
| Product analytics | ❌ |
| Uptime alerting | ❌ |

---

## Security

| Item | Status |
|---|---|
| RLS + RPC-only writes | ✅ |
| pgTAP security suite | ✅ |
| Anon-only clients | ✅ |
| No service_role in apps | ✅ |
| Secrets not committed | ✅ (env gitignored) |
| Penetration test / threat review | ❌ |
| Android release signing | ❌ |
| Member PII logging scrubbed | 🟡 (design; verify when members ship) |

---

## Deployment

| Item | Status |
|---|---|
| Three projects model + scripts | ✅ |
| CI format/analyze/test/pgTAP | ✅ |
| Staging promotion gate | ✅ (scripted) |
| Production typed confirm | ✅ (scripted) |
| Web hosting (Pages/Vercel/etc.) | ❌ not in repo |
| Mobile store release pipeline | ❌ |
| Edge Functions | ❌ none |
| Storage buckets | ❌ none |

---

## Go-live minimum (recommended)

1. Epic 7 exit + members + inventory + offline critical path  
2. PITR + restore drill  
3. Remove/disable all Owner Web fixture metrics in production builds  
4. Release signing + store builds  
5. Real trading-day rehearsal at pilot centre with drawer balance  
6. On-call / backup owner for DB  

Until then: **local/staging demo only**, not commercial SaaS launch.
