# 20 — Project Scorecard

Honest scores from codebase audit (0–10).  
**10** = production-grade for that area · **0** = absent.

| Area | Score | Rationale |
|---|---|---|
| **Flutter** | **5.5 / 10** | Core trading screens real; dual demo path; no members/inventory/offline; thin feature tests |
| **Web** | **4.0 / 10** | Auth + live floor/shift/checkout solid; majority of IA is fixture chrome; no tests; no router |
| **Database** | **9.0 / 10** | Excellent P0 schema, constraints, algorithms, seed discipline; minor doc drift on extras |
| **Architecture** | **8.0 / 10** | Clear RPC/RLS/Riverpod patterns; dual Flutter apps and fixture Owner Web dilute purity |
| **Security** | **8.5 / 10** | RLS, RPC boundaries, pgTAP, anon-only clients; release signing / PITR / MFA still open |
| **Testing** | **5.5 / 10** | Strong pgTAP; Flutter unit/guards only; zero web tests; harness assertion stale |
| **Performance** | **4.0 / 10** | No proven 40-station / offline cache; floor uses client timers + poll; no profiling evidence |
| **Documentation** | **8.0 / 10** | Deep contract docs + this handover; some stale CLAUDE/README/supabase README lines |
| **Production readiness** | **3.0 / 10** | Demoable trading path; not launchable as multi-tenant SaaS |

### Aggregate

| Roll-up | Score |
|---|---|
| Engineering foundations | **8.2** |
| Staff product completeness | **5.0** |
| Owner product completeness | **3.5** |
| Commercial SaaS readiness | **1.5** |
| **Overall product** | **~5.0 / 10** |

---

## Interpretation

- **Do hire / onboard** using `docs/HANDOVER/` + DECISIONS — foundations are strong.  
- **Do not sell** Owner dashboards/reports/CRM as live.  
- **Do prioritize** Epic 7 exit → members → inventory → offline → PITR before calling MVP done.
