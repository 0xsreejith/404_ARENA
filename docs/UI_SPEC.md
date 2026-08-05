# Mobile UI

Staff-facing Flutter application, phone and tablet.

Governing decisions: `DECISIONS.md`. Scope: `MVP.md`.

---

## 1. Principles

Counter UI is used while a customer is standing there.

- Large touch targets
- Important state visible without opening a detail screen
- Minimal typing
- Avoid dialogs where an inline control works
- No decorative animation
- Never imply that an offline action reached the server

Starting a normal walk-in session takes a few taps and no keyboard.

---

## 2. Theme

Dark, gaming-oriented.

| Token | Value |
|---|---|
| Background | `#07070A` |
| Surface | `#101018` |
| Surface raised | `#171A20` |
| Primary text | `#E8EAF0` |
| Accent / live / success | `#7CFF4F` |
| Warning / ending | `#FFB020` |
| Danger / overtime / destructive | `#FF4444` |
| Muted / unavailable | 45% opacity on primary text |

Green means normal and live. Amber means ending or attention. Red means
overtime, error, or destructive.

Colour is never the only signal — every state also carries a label, so the
floor reads correctly for colour-blind staff and in bright light.

---

## 3. Station state derivation — normative

Stored state is `stations.status` plus the live session's timestamps. The
presentation state is computed on the client (D06) and stored nowhere.

Evaluate in order; first match wins:

| # | Condition | State | Colour |
|---|---|---|---|
| 1 | `station.status = 'inactive'` | `inactive` | hidden by default |
| 2 | `station.status = 'maintenance'` | `maintenance` | muted |
| 3 | No session with status `active` or `paused` | `idle` | neutral |
| 4 | `session.status = 'paused'` | `paused` | distinct outline, dimmed timer |
| 5 | `planned_end_at != null` and `now > planned_end_at` | `overtime` | red |
| 6 | `planned_end_at != null` and `planned_end_at - now <= arena_settings.ending_threshold_minutes` (default 10) | `ending` | amber |
| 7 | otherwise | `live` | green |

**Open-time sessions have `planned_end_at = null` and therefore never render
`ending` or `overtime`.** They render `live` with elapsed time counting up.
This is intended, not a gap (D06).

`reserved` is not a P0 state (D28).

A station with a `completed` but unbilled session renders `idle` with an
**Unbilled** badge, and tapping it opens checkout.

---

## 4. Floor

The floor is the home screen and the centre of the staff experience.

Station card shows:

- station name
- station type
- presentation state, as colour **and** label
- timer — counting down for fixed-duration, counting up for open-time
- member name or `Walk-in`
- game, when set
- player count, when greater than 1
- **Unbilled** badge when applicable

Grouped by zone, ordered by `sort_order`. A summary strip shows counts per
state.

The app bar always shows the connectivity state and the age of the last
successful sync (`OFFLINE.md` §1).

Only the timer text inside a card rebuilds per second (`ARCHITECTURE.md` §7).

---

## 5. Navigation

Navigation is **derived from permissions**. A user without `member.view` does
not see a Members tab (audit finding C16). An empty section is never shown.

**Phone — bottom navigation**

| Tab | Permission |
|---|---|
| Floor | `session.view` |
| Members | `member.view` |
| Stock | `product.view` |
| More | always |

**More** contains: Shift (`shift.view`), Sync Issues (always), Settings and
account (always), and Back of House — visible to anyone holding **any** of
`arena.settings`, `pricing.manage`, `product.manage`, `station.update`,
`staff.manage`, `permissions.manage`, or `report.view`. Inside Back of House,
each section is gated by its own code from `API.md` §11.

**Tablet — persistent navigation rail**

Floor · Members · Stock · Shift · More, filtered the same way.

---

## 6. Start session

Reached by tapping an `idle` station.

1. Station header — name, type, zone
2. Billing plan — plans valid for this station type; single tap
3. Member — `Walk-in` is the default and pre-selected; a search field is
   secondary
4. Player count — stepper, defaults to 1, capped at `seat_capacity`
5. Game — optional, skippable
6. **Start**

Walk-in with a default plan is two taps from the floor. Nothing on this screen
blocks on a network call except the final Start.

Offline: Start is available and queues (`OFFLINE.md` §2). Member search is not
available offline; the sheet says so and offers Walk-in.

A blocked member is refused with the block reason shown.

---

## 7. Active session

The timer dominates the screen.

Actions, each gated by its permission:

- Pause / Resume — `session.pause` / `session.resume`
- Extend — `session.extend`, **hidden for open-time plans** (there is nothing
  to extend)
- Add item — `inventory.sell`
- Stop & bill — `session.stop`
- Cancel session — `session.cancel`, destructive styling, confirmation required

Also shown: elapsed and remaining time, plan name, member or walk-in, game,
player count, and the session timeline from the audit log (`report.view`).

Offline: only Stop is available. Every other action is visibly disabled with
the reason "Needs internet".

### Unbilled sessions

A completed session with no settled order appears in an **Unbilled sessions**
list, reachable from the floor summary strip and badged when non-empty.

This exists because a session stopped offline is completed but unbilled (D15).
It is a required P0 surface.

---

## 8. Checkout — online only

Opened by **Stop & bill**, or by tapping an unbilled session.

Shows, in order:

- Play charge, with the time range, elapsed time, and rounded billable time
- Product lines
- Discount, when applied — amount, reason, who authorised it
- Tax, broken out by **component** as configured — an Indian arena shows CGST
  and SGST as separate lines, an inter-state rate shows one IGST line. The
  component names come from the order's tax snapshot; the UI never assumes a
  jurisdiction (D31)
- **Total**

Prices are **tax-inclusive** for the pilot (D32): the total equals subtotal
minus discount, and tax is shown as a breakdown of that total, not added to it.
The line reads "incl. tax" so staff and customers are not confused into
expecting an addition. If an arena is configured tax-exclusive, tax appears as
an added line instead — the label follows the snapshot, not a constant.

Every figure comes from `order_preview` on the server. Flutter never computes a
bill (D05). While the preview is refreshing, the previous total is greyed
rather than replaced by a spinner.

**Discount** (`discount.apply`): flat or percent, with a **mandatory reason**.
Save is disabled until a reason is entered.

**Payment:** cash, UPI, card. One payment in P0; the layout leaves room for
split later. UPI and card accept an optional reference.

Settling shows the receipt number and returns to the floor with a confirmation
that names the station now available.

**An open shift is required to settle.** With no shift open, checkout shows the
bill and offers "Open a shift" inline rather than failing at the payment tap.

Offline, checkout is unreachable. The Stop & bill action still works and
explains that billing resumes when connectivity returns.

---

## 9. Members — online only

- Search by phone or name, minimum 3 characters, server-side, capped at 20
  results
- Create member: name and phone required, date of birth optional; duplicate
  phone offers the existing member
- Phone entry accepts a plain 10-digit mobile number and displays it that way.
  Storage is canonical E.164 and normalisation happens **server-side** (D36) —
  the client never decides what the canonical form is
- Profile: name, phone, blocked state, last 10 sessions, plus CRM stats /
  notes / timeline when returned by `member_get`
- Block / unblock with a reason (`member.block`)
- Wallet balance, loyalty points/tier, and membership badge are **server
  fields only** (D28a) — never client-invented

Offline, the Members tab is read-only for cached members and explains why.

---

## 10. Stock — online only for writes

- Product list with price and current stock
- Low-stock highlighted in amber; negative stock highlighted in red as a
  data-quality warning (D20)
- Add to an active session, or start a counter sale (`inventory.sell`)
- Adjust stock: restock, wastage, staff use, breakage, correction —
  reason required for corrections

Reads work offline from cache and are labelled as possibly stale.

---

## 11. Shift — online only

- Current shift: opened by, opened at, opening float, live totals
- Open shift: opening float only
- Summary: sales split by play and product, discount total, tax total, payment
  breakdown by method, expected cash
- Close: counted cash entry, variance shown immediately, **notes required when
  variance is non-zero** (D29)
- Close is refused while any order is open, and says which ones
- Unbilled sessions are shown as a count with a link. They do **not** block
  closing — their revenue belongs to the shift that eventually takes the
  payment (D08) — but staff should see the number before they close

---

## 12. Sync Issues

Reachable from the connectivity indicator anywhere in the app, and surfaced
automatically when anything fails.

- Pending operations with the next retry time
- Failed and conflicting operations with a plain-language reason
- Age of the last successful sync
- Retry and Discard, both online-only; Discard requires `session.cancel` and is
  audited server-side before the local row is removed

Example copy: *"Station PC-04 was already in use when this reached the server.
The session was not created."*

---

## 13. Connectivity and staleness

| State | Presentation |
|---|---|
| `online` | Small green dot with the last-sync age |
| `degraded` | Amber dot, "Reconnecting…" |
| `offline` | Amber banner: "Offline — sessions can start and stop, billing is unavailable" |
| `stale` | Red blocking banner: "Not synced for over 24 hours — read only. Reconnect to continue." |

An action unavailable offline is **visibly disabled with a reason**, never
hidden and never allowed to fail after the tap.

---

## 14. Not in the P0 UI

Nothing in the interface hints at features that do not exist:

reservations · memberships · wallet and coins · receipts printing or sharing ·
maintenance tickets · assets and QR scanning · expenses · notifications ·
tournaments · leaderboards · split payment · refunds · multi-location switching
· reporting beyond the shift summary.
