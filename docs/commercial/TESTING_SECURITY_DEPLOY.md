# Arena OS — Testing, Security, Deployment & Production

---

## 1. Testing strategy

| Layer | Tool | Scope |
|---|---|---|
| DB security / money | pgTAP | Isolation, RLS, algorithms, RPC vectors |
| RPC contract | pgTAP + SQL fixtures | Every new RPC |
| Flutter unit | `flutter test` | Money, mappers, controllers |
| Flutter golden | golden tests | StationCard, shell chrome |
| Flutter integration | integration_test | Login→floor→stop→pay |
| Web | Vitest + Playwright | Owner critical paths |
| Load | k6 | floor_snapshot, settle |
| Chaos | manual + scripts | Offline outbox, webhook replay |

**Gate:** CI red blocks merge. Money tests cannot be skipped.

---

## 2. Security checklist

- [ ] No `service_role` in any client or mobile binary  
- [ ] Anon key only; RLS on  
- [ ] RPC `SECURITY DEFINER` + `require_permission`  
- [ ] Actor never a parameter  
- [ ] Members / wallets / loyalty: no broad SELECT  
- [ ] Audit append-only  
- [ ] Secrets in Supabase vault / CI secrets  
- [ ] MFA for owners (COMM)  
- [ ] Device trust revoke path  
- [ ] Rate limit Auth + sensitive RPCs  
- [ ] Webhook signature verify + idempotency  
- [ ] Impersonation audited + time-boxed  
- [ ] PITR on; restore drill recorded (D37)  
- [ ] Dependency scanning (CI)  
- [ ] Storage bucket policies (photos private)  

---

## 3. CI/CD

```
PR → format + analyze + flutter test
   → web lint/build
   → supabase db lint
   → pgTAP job (ephemeral DB)
   → (optional) Playwright smoke

main → deploy staging (migrations via db.sh push staging)
tag  → production push with typed confirmation (db.sh)
     → store mobile/web artifacts
```

Promotion: development → staging → production (D34). Never seed production with fixtures (D33).

---

## 4. Deployment guide (summary)

1. Create three Supabase projects  
2. Configure Auth URLs per surface  
3. `db.sh push` migrations in order  
4. Set Edge secrets (payment providers)  
5. Deploy web/portal/platform to Cloudflare Pages / Vercel / similar  
6. Distribute staff/customer apps (stores + MDM for tablets)  
7. Configure tenant branding + tax + plans **as data**  
8. Enable PITR; name backup owner in repo docs  

---

## 5. Monitoring

| Signal | System |
|---|---|
| API errors / latency | Supabase metrics + APM |
| RPC error rates by code | Log drain |
| Payment webhook failures | Edge logs + alert |
| Shift close variance outliers | Report job |
| Agent offline | Telemetry heartbeat |
| App crash | Sentry/Crashlytics |
| Uptime | External probe on Auth + Rest |

Alerts: page on settle failure spike; ticket on webhook retry exhaustion.

---

## 6. Production checklist (tenant go-live)

- [ ] Pricing/tax/receipt configured by tenant (not fixtures)  
- [ ] Staff roles assigned  
- [ ] Open shift procedure trained  
- [ ] Drawer float policy  
- [ ] Printer/receipt format tested  
- [ ] Backup/restore note current  
- [ ] Feature flags set for plan  
- [ ] Legal: terms, privacy, consent  
- [ ] Support contact + runbook  
- [ ] Shadow-run day (notebook parallel) before cutover  

---

## 7. Quality target

**10/10 production** means: money correct, isolation proven, UX parity with design spec, operable multi-branch SaaS, observable, restorable, and no hardcoded pilot tenant — not “all COMM modules on day one,” but **every module specified and wave-shippable without re-architecture**.
