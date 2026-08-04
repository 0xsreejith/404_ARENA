# Arena OS — Target Database Schema (Commercial)

**Doctrine:** Additive migrations only. Preserve 28 P0 tables. Extend with new tables; never break composite tenant FKs, append-only money, or RLS posture.

**Money:** `numeric(12,2)` · **Qty:** `numeric(12,3)` · **Actor:** never a client column for authz

---

## 1. P0 tables (existing — authoritative in `docs/DATABASE.md`)

organizations · arenas · arena_settings · profiles · permissions · roles · role_permissions · arena_users · devices · zones · station_types · stations · games · billing_plans · tax_rates · tax_rate_components · members · products · product_stock · inventory_movements · shifts · sessions · orders · order_items · payments · receipt_counters · idempotency_keys · audit_logs

---

## 2. Commercial expansions (by domain)

Each group: new tables · key columns · notes. All arena-owned tables include `arena_id` + composite FKs unless marked **platform**.

### 2.1 Auth / devices / PIN

| Table | Purpose |
|---|---|
| `staff_pins` | `user_id`, hashed PIN, arena_id, failed_attempts |
| `trusted_devices` | extends devices: trusted_at, revoked_at, label |
| `auth_challenges` | QR login nonces, expiry |

### 2.2 CRM members (extend `members`)

Additive columns on `members` **or** `member_profiles` 1:1:

photo_path · email · whatsapp · address_json · gender · emergency_contact_json · anniversary · marketing_consent · referral_code · referred_by_member_id · documents_json

| Table | Purpose |
|---|---|
| `member_stats` | materialised: visits, hours, spend, last_visit, favourites |
| `member_notes` | timed notes by staff |
| `member_documents` | storage refs |

### 2.3 Memberships & loyalty & wallet

| Table | Purpose |
|---|---|
| `membership_plans` | tier, period, price, benefits_json |
| `member_memberships` | member, plan, start/end, auto_renew, status |
| `loyalty_accounts` | member points balance (materialised) |
| `loyalty_ledger` | append-only points |
| `loyalty_tiers` | thresholds |
| `achievements` / `member_achievements` | catalogue + grants |
| `wallets` | member wallet |
| `wallet_ledger` | append-only |
| `coupons` / `coupon_redemptions` | |
| `gift_cards` / `gift_card_ledger` | |

### 2.4 Floor layout & station assets

| Table | Purpose |
|---|---|
| `floor_layouts` | named layouts |
| `station_positions` | x,y,w,h on layout |
| `station_assets` | controllers, headsets, linked station |
| `station_telemetry` | last heartbeat, temp, metrics_json |
| `station_commands` | WoL/restart queue |
| `maintenance_tickets` | faults, broken state |

### 2.5 Games library

| Table | Purpose |
|---|---|
| `game_genres` | |
| `games` | extend existing |
| `station_games` | installed title per station |
| `game_launchers` | steam/epic/… |
| `game_licenses` | seat/console license notes |

### 2.6 Sessions commercial

| Table | Purpose |
|---|---|
| Extend `sessions` | transfer_of, parent_session_id, package_upgrade_id |
| `session_events_ext` | **avoid** — keep using `audit_logs` (D22) |

### 2.7 Bookings & waitlist

| Table | Purpose |
|---|---|
| `bookings` | member, station/type, start/end, status, deposit_order_id |
| `booking_resources` | multi-station holds |
| `waitlist_entries` | |
| `recurrence_rules` | |

### 2.8 Pricing rules

| Table | Purpose |
|---|---|
| `pricing_rules` | happy hour, tier price, night package |
| `billing_plan_rules` | link plans ↔ rules |

### 2.9 Inventory commercial

| Table | Purpose |
|---|---|
| `product_categories` | |
| `suppliers` | |
| `purchase_orders` / `purchase_order_lines` | |
| `stock_transfers` / `stock_transfer_lines` | inter-arena |
| `product_barcodes` | |
| `product_bundles` / `bundle_items` | |

### 2.10 POS / finance

| Table | Purpose |
|---|---|
| `expenses` | |
| `cash_movements` | payouts, drops, bank deposit (extends D29) |
| `payment_provider_events` | webhook log |
| `tips` | optional on orders |
| `refunds` | link reversing payments (shape exists via reverses_payment_id) |

### 2.11 Shift / HR

| Table | Purpose |
|---|---|
| `attendance_punches` | clock in/out |
| `leave_requests` | |
| `staff_tasks` | |
| `commission_rules` | |

### 2.12 Tournaments & events

| Table | Purpose |
|---|---|
| `tournaments` · `tournament_entries` · `tournament_brackets` · `tournament_matches` | |
| `events` · `event_resources` | |

### 2.13 Notifications & marketing

| Table | Purpose |
|---|---|
| `notification_templates` | |
| `notification_outbox` | channel, payload, status |
| `campaigns` · `campaign_deliveries` | |
| `referrals` | |

### 2.14 Reports

Prefer **SQL views / RPCs** over stored report tables; optional `report_snapshots` for heavy async jobs.

### 2.15 AI

| Table | Purpose |
|---|---|
| `insight_jobs` · `insight_results` | flag-gated; nullable |

### 2.16 Platform (no arena_id on billing entities)

| Table | Purpose |
|---|---|
| `platform.tenants` | org link, status |
| `platform.plans` · `subscriptions` · `invoices` · `usage_records` | |
| `platform.feature_flags` · `tenant_flags` | |
| `platform.custom_domains` | |
| `platform.support_cases` · `impersonation_sessions` | audited |

### 2.17 Integrations

| Table | Purpose |
|---|---|
| `integration_accounts` | provider, encrypted ref to secrets |
| `webhook_receipts` | idempotency |

---

## 3. RLS pattern (unchanged)

1. No client writes  
2. RLS enabled  
3. `arena_id in app.current_arena_ids()` for reads  
4. Members / ledgers with PII: **no SELECT**; RPC only  
5. Platform schema: not exposed to `authenticated` arena users  

---

## 4. Migration policy

- Forward-only  
- One domain per migration wave  
- pgTAP for isolation + money on every financial ledger  
- Seed fixtures `[FIXTURE]` only in non-prod (D33)
