# 11 — Current MVP (What a Shop Can Do TODAY)

Assumes: local or remote Supabase with migrations applied, seed loaded, staff signed in with password, shift opened.

This is **operational capability**, not formal ROADMAP M7 exit.

---

## Trading day checklist

| Capability | Today? | Notes |
|---|---|---|
| Sign in (email/password) | **YES** | Flutter + Web |
| Select branch / arena | **YES** | |
| Register device telemetry | **YES** | |
| View floor / stations | **YES** | Live snapshot |
| Filter zones | **YES** | Flutter |
| Open shift | **YES** | Required before settle |
| Start session | **YES** | Plan + players; **no member/game picker in production UI** |
| Pause session | **YES** | |
| Resume session | **YES** | |
| Stop session | **YES** | Frees station |
| See unbilled sessions | **YES** | |
| Open checkout / preview bill | **YES** | Server totals |
| Apply discount | **PARTIAL** | RPC + Flutter; permission needed |
| Add snacks to bill | **PARTIAL** | RPC exists; UI limited |
| Settle payment (cash/card/upi) | **YES** | Single tender; needs open shift |
| Split payment | **NO** | |
| Void open order | **PARTIAL** | RPC; weak UI |
| Close shift + variance | **YES** | |
| Print receipt | **NO** | |
| Search / create members | **NO** | Schema only; lobby/web mock |
| Block member | **NO** | |
| Membership / packages sell | **NO** | |
| Wallet / coins | **NO** | Demo only |
| Receive / adjust stock | **NO** | |
| Low-stock alerts (real) | **NO** | Fixture on web |
| Reports (real) | **NO** | Web mock |
| Expenses | **NO** | Web mock |
| Offline start/stop | **NO** | |
| Multi-branch SaaS admin | **NO** | |
| Second tenant without code | **NO** | M10 not done |

---

## Practical pilot script

1. Seed DB → sign in as owner/manager/staff  
2. Open shift with float  
3. Start session on idle station  
4. Pause/resume optionally  
5. End & bill → preview → settle  
6. Close shift with counted cash  

That path is the **real** product today.

---

## Do not demo as real

- Lobby PIN login / members / stock / coins  
- Owner dashboard charts and report tabs  
- Web Add Member / Restock / Staff permission toggles  
- “SYNCED 12s AGO” / Export queued  

---

## Formal MVP gap

`docs/MVP.md` / ROADMAP M7 also require: members P0, inventory P0, offline start/stop, full trading-day proof at 404, PITR. Those are **not** available today.
