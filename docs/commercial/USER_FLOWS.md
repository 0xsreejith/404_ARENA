# Arena OS — User Flows

Flows are acceptance narratives. RPCs named in `API_SURFACE.md`.

---

## F1 — Walk-in play → pay (CORE)

1. Staff unlocks (PIN/email)  
2. Selects arena (if multi)  
3. Opens shift (if none)  
4. Floor → idle station → Start (plan, optional member, seats, game)  
5. Session live → optional pause/resume/extend/snacks  
6. Stop → unbilled  
7. Checkout → preview (server) → pay cash/UPI/card/split → receipt  
8. Station idle; shift cash expected updates  

**Offline:** steps 4 start + 6 stop may queue; step 7 blocked.

---

## F2 — Member CRM create → session

1. Members → Add → phone normalised E.164  
2. Profile photo optional  
3. Start session with member attached  
4. Stats update on settle  

---

## F3 — Membership purchase

1. Owner configures plan  
2. Customer app / counter sells membership  
3. Wallet or POS payment  
4. Benefits apply to pricing_rules  

---

## F4 — Online booking → check-in

1. Customer books slot + deposit  
2. Reminder notification  
3. Staff check-in → auto or assisted session_start  
4. No-show → fee / waitlist promote  

---

## F5 — Inventory receive → sell

1. PO create → receive movements  
2. Counter sale or session add product  
3. Settle → sale movement  
4. Low-stock notification  

---

## F6 — Shift close

1. Manager Shift → summary  
2. Counted cash → variance + notes  
3. Close; next staff cannot settle without new open  

---

## F7 — Multi-branch owner

1. Owner Web central dashboard  
2. Switch arena or org rollup reports  
3. Transfer stock arena A→B  

---

## F8 — Tournament day

1. Create tournament + fee product  
2. Registrations / brackets  
3. Stations reserved via bookings  
4. Scores → leaderboard → prizes wallet credit  

---

## F9 — Technician maintenance

1. Mark station maintenance  
2. Ticket + telemetry  
3. Agent restart/WoL optional  
4. Return to active  

---

## F10 — SaaS provision

1. Super Admin creates tenant + plan  
2. `provision_arena`  
3. Owner invite  
4. Feature flags  
5. Custom domain / branding  

---

## F11 — Wallet top-up & pay

1. Customer tops up (provider webhook → ledger)  
2. Checkout method wallet  
3. Ledger debit; receipt  

---

## F12 — Refund

1. Manager refund RPC → reversing payment  
2. Optional restock  
3. Audit + report  

---

## F13 — Emergency lock

1. Owner triggers arena lock  
2. New starts rejected  
3. Live sessions can still stop/settle  
4. Unlock audited  

---

## F14 — AI insight (optional)

1. Flag on → request job  
2. Worker writes results  
3. Dashboard cards show forecast with model metadata  
4. If unavailable → explicit empty / not_implemented  
