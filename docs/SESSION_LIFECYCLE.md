# Arena OS — Session Lifecycle & State Machine Specification

---

## 1. Overview

A **Session** models customer play time on a station. It captures the billing plan, player count, start time, pause intervals, pricing snapshot, and termination state.

- **Stored Statuses (PostgreSQL)**: Exhaustively `active`, `paused`, `completed`, `cancelled`.
- **Derived Presentation States (Client UI)**: Computed on client runtimes (Flutter & React) and stored nowhere:
  `idle` · `live` · `ending` · `overtime` · `paused` · `maintenance` · `inactive`

---

## 2. State Machine Diagram

```
 [Station: Active] ──(session_start)──> [Session: active]
                                              │    ▲
                                (session_pause)    │ (session_resume)
                                              ▼    │
                                        [Session: paused]
                                              │
                                       (session_stop)
                                              ▼
                                      [Session: completed]
                                              │
                                      (Move to Unbilled Queue)
                                              │
                                       (order_settle in Epic 3)
                                              ▼
                                      [Order: settled]
```

---

## 3. Legal State Transitions

| Initial State | Action / RPC | Target State | Side Effects & Invariants |
|---|---|---|---|
| Station `active` (no live session) | `session_start` | Session `active` | Station partial unique index engaged; captures `pricing_snapshot`; sets `planned_end_at` for packages |
| Session `active` | `session_pause` | Session `paused` | Sets `paused_at = now()`; timer freezes on UI |
| Session `paused` | `session_resume` | Session `active` | Calculates `v_pause_seconds = now() - paused_at`; increments `total_paused_seconds`; clears `paused_at`; extends `planned_end_at` by `v_pause_seconds` |
| Session `active` or `paused` | `session_stop` | Session `completed` | Sets `ended_at = now()`, `ended_by_user_id = auth.uid()`, `end_reason = 'normal'`; station partial unique index released; station returns to `idle`; session moves to **Unbilled Queue** |
| Session `completed` (unbilled) | `order_settle` (Epic 3) | Order `settled` | Financial settlement; tax extraction & receipt series sequence assignment |

---

## 4. Illegal Transitions & Validation Matrix

| Initial State | Attempted Action | Result | Error Code | Reason |
|---|---|---|---|---|
| Station `maintenance` / `inactive` | `session_start` | **BLOCKED** | `invalid_state` | Station is not available for new walk-ins |
| Station with live session | `session_start` | **BLOCKED** | `conflict` | Station already has a live session (`sessions_one_live_per_station`) |
| Session `paused` | `session_pause` | **BLOCKED** | `invalid_state` | Session is already paused |
| Session `active` | `session_resume` | **BLOCKED** | `invalid_state` | Session is already active |
| Session `completed` | `session_pause` | **BLOCKED** | `invalid_state` | Completed sessions are terminal |
| Session `completed` | `session_resume` | **BLOCKED** | `invalid_state` | Completed sessions are terminal |
| Session `completed` | `session_stop` | **BLOCKED** | `invalid_state` | Completed sessions are terminal |
| Station with live session | `station_set_status(maintenance)` | **BLOCKED** | `conflict` | Cannot place station in maintenance while a session is live |

---

## 5. Client Derived Presentation State Algorithm

Computed on client every 1 second:

```ts
function deriveStationState(station, session, now) {
  if (station.status === 'maintenance') return 'MAINTENANCE';
  if (station.status === 'inactive') return 'INACTIVE';
  if (!session) return 'IDLE';
  if (session.status === 'paused') return 'PAUSED';
  if (!session.planned_end_at) return 'LIVE'; // Open-time hourly plan

  const remainingSeconds = (new Date(session.planned_end_at) - now) / 1000;
  if (remainingSeconds <= 0) return 'OVERTIME';
  if (remainingSeconds <= 600) return 'ENDING'; // 10 minutes or less
  return 'LIVE';
}
```

---

## 6. Database Invariants

1. **Station Concurrency**: Unique partial index `sessions_one_live_per_station ON sessions (station_id) WHERE status IN ('active', 'paused')`.
2. **Actor Attribution**: `started_by_user_id` and `ended_by_user_id` are derived server-side via `app.current_actor_id()` (`auth.uid()`).
3. **Pricing Immutability**: `pricing_snapshot` JSONB is set at `session_start` and never modified.
4. **Audit Transactional Binding**: `session.started`, `session.paused`, `session.resumed`, and `session.stopped` write an `audit_logs` record in the exact same Postgres transaction.
