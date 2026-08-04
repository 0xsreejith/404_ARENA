# Arena OS — Checkout & Billing Business Rules Specification

---

## 1. Architectural Principles & Financial Model

1. **Server Authoritative**: All monetary calculations (play charges, subtotals, discounts, tax allocations, totals, and balances due) are computed exclusively inside PostgreSQL `SECURITY DEFINER` RPCs. Flutter and React UI act purely as presentation layers.
2. **Numeric Precision**:
   - **PostgreSQL**: Monetary amounts are strictly `numeric(12,2)`. Percentages are `numeric(5,2)`. Quantities are `numeric(12,3)`. Float / double precision types are strictly forbidden.
   - **Client Runtimes (Dart / TypeScript)**: Money is represented as minor-unit integers (`int`), parsed directly from string representations.
3. **Idempotency & Reentrancy**: Every financial mutation RPC takes a client-supplied `p_idempotency_key text`. Re-submitting an operation with the same key returns the existing cached response without re-calculating or re-settling.
4. **Append-Only Auditing**: `payments` and `audit_logs` tables are append-only. Financial mutations write audit trail records in the exact same database transaction.
5. **Historical Immutability**: Historical settled orders and receipts are strictly immutable. Configuration updates (such as changing tax rates or billing plans) never alter historical bills.

---

## 2. Play Charge Computation Algorithm

Play charges are computed server-side from the session's immutable `pricing_snapshot` (captured at `session_start`).

```
1. elapsed_seconds = (ended_at - started_at) - total_paused_seconds
2. elapsed_minutes = ceil(elapsed_seconds / 60)
3. if elapsed_minutes <= grace_minutes -> amount = 0.00, stop

4. open_time:
   a. billable = max(elapsed_minutes, minimum_billable_minutes)
   b. billable = round_to(billable, rounding_increment_minutes, rounding_mode)
   c. amount   = hourly_rate * billable / 60

5. fixed_duration:
   a. overrun = max(0, elapsed_minutes - duration_minutes - grace_minutes)
   b. blocks  = 1 + ceil(overrun / duration_minutes)
   c. amount  = fixed_price * blocks

6. amount = round(amount, 2)  -- half-up
```

---

## 3. Order & Itemization Hierarchy

```
Order (session_id or counter sale, subtotal, discount_total, tax_total, total, paid_total, balance_due)
  ├── Order Item 1: Play Charge (type = 'play', session_id)
  ├── Order Item 2: Product Sale (type = 'product', product_id, quantity)
  └── Order Item N...
```

- An open session produces at most one active order (`UNIQUE (session_id) WHERE status <> 'void'`).
- A counter sale order has `session_id = NULL`.

---

## 4. Manager Discount Rules

- **Authorisation**: Discounts require a staff member holding `discount.apply` permission code (`discount_authorised_by_user_id`).
- **Discount Types**:
  - `flat`: Amount in minor units/currency decimal. `discount_total = min(discount_value, subtotal)`.
  - `percent`: Percentage value $\le 100.00\%$. `discount_total = round(subtotal * discount_value / 100, 2)`.
- **Reason Requirement**: `discount_reason` is mandatory whenever a discount is applied.
- **Proportional Line Allocation**: `discount_total` is allocated proportionally across order line items using the largest-remainder method so that line discount sums equal `discount_total` exactly without rounding drift.

---

## 5. Tax Allocation & Split Algorithm

Governed by `arena_settings.prices_include_tax` (Tax-Inclusive vs Tax-Exclusive):

1. **Net Line Calculation**: `net_i = line_subtotal_i - discount_amount_i`
2. **Tax Extraction**:
   - **Exclusive**:
     $$\text{taxable\_amount} = \text{net}$$
     $$\text{tax\_amount} = \text{round}(\text{net} \times \frac{\text{percent}}{100}, 2)$$
     $$\text{line\_total} = \text{net} + \text{tax\_amount}$$
   - **Inclusive** (Pilot Default):
     $$\text{taxable\_amount} = \text{round}(\frac{\text{net}}{1 + \text{percent}/100}, 2)$$
     $$\text{tax\_amount} = \text{net} - \text{taxable\_amount}$$
     $$\text{line\_total} = \text{net}$$
3. **Component Breakdown (Largest Remainder)**:
   - For each component in `sort_order`:
     $$\text{raw}_j = \text{taxable\_amount} \times \frac{\text{component.percent}}{100}$$
     $$\text{amount}_j = \lfloor \text{raw}_j \rfloor_2$$
   - Distribute remaining unallocated cents ($\text{tax\_amount} - \sum \text{amount}_j$) as 1-paisa increments by largest remainder $(\text{raw}_j - \text{amount}_j)$, breaking ties by `sort_order`.
   - Guarantees $\sum \text{component.amount} = \text{tax\_amount}$ exactly (CGST + SGST or IGST).

---

## 6. Payment Settlement & Split Payment Rules

- **Supported Payment Methods**: `cash`, `card`, `upi`.
- **Shift Linkage**: Every payment row captures `shift_id` (pointing to the currently open shift `app.current_shift_id()`). Cash reconciliation follows `payments.shift_id` exclusively.
- **Split Payments**: An order can be settled across multiple payment transactions (e.g., ₹500 Cash + ₹500 UPI).
- **Trigger Maintenance**: `orders.paid_total` is updated automatically via trigger on `payments` insert.
- **Settlement Completion**: Order status transitions `open` $\rightarrow$ `settled` when `paid_total == total`. At that moment:
  - `settled_at` and `settled_by_user_id` are set.
  - A unique `receipt_number` is generated and assigned.
  - Product stock movements are written (`type = 'sale'`).

---

## 7. Receipt Generation Policy

- `receipt_number` is assigned server-side at settlement in `order_settle` via
  `app.next_receipt_number` (never a hardcoded prefix in RPC bodies).
- Series key is computed by `app.receipt_series(arena_id, business_date)` based on `arena_settings.receipt_series_mode` (`fixed`, `monthly`, `yearly`, `financial_yearly`).
- Receipt sequence is atomically incremented via `receipt_counters`.
- Format comes from `arena_settings.receipt_number_format` with `{prefix}`,
  `{series}`, and `{sequence}` substituted by `app.render_receipt_number`
  (D13). Example when configured: `FIX/2026/000001`.

---

## 8. Audit Log & Immutability

- Financial transactions (`order.created`, `discount.applied`, `payment.recorded`, `order.settled`, `order.voided`) write audit entries inside the same transaction.
- Once an order reaches `settled` status, any mutation attempt is rejected with `invalid_state`.

---

## 9. Epic 3C integrity (implementation note)

`order_preview` and `order_settle` must call `app.compute_order_totals` with
tax payloads from `app.tax_input_from_rate`. Play amounts must call
`app.play_charge` (via `app.compute_play_charge` / normalized snapshots).
Hardcoded tax divisors (e.g. `1.18`) or receipt prefixes in RPC SQL are bugs.