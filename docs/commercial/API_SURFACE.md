# Arena OS — Commercial API Surface

**Transport:** PostgREST RPC + RLS SELECT  
**Params:** `p_*` · **Errors:** codes in `docs/API.md`  
**Idempotency:** required on financial / booking create mutations

This catalogue lists **domains**. Existing RPCs stay; new ones add. Full param matrices land with each migration (DoD).

---

## A. Existing (shipped / partial)

| RPC | Domain |
|---|---|
| `me` · `register_device` | Auth context |
| `floor_snapshot` · `station_set_status` | Floor |
| `session_start\|pause\|resume\|stop` | Sessions |
| `checkout_open` · `order_add_product` · `order_apply_discount` · `order_preview` · `order_settle` · `order_void` | POS |
| `provision_arena` | Platform bootstrap (service_role) |

---

## B. Auth & staff

`auth_pin_set` · `auth_pin_verify` · `auth_qr_challenge` · `auth_qr_consume` · `device_trust` · `device_revoke` · `session_list` · `session_revoke` · `password_recovery_request` (Auth API) · `mfa_*` (Auth API)

---

## C. Roles & staff admin

`staff_invite` · `staff_set_active` · `role_create` · `role_update` · `role_set_permissions` · `role_clone` · `permission_catalogue`

---

## D. Floor & stations

`zone_upsert` · `station_upsert` · `station_clone` · `station_bulk_update` · `floor_layout_get` · `floor_layout_save` · `station_position_save` · `arena_emergency_lock` · `station_command_enqueue` · `telemetry_ingest` (agent)

---

## E. Games

`game_upsert` · `station_game_set` · `launcher_catalogue`

---

## F. Sessions (complete)

`session_extend` · `session_cancel` · `session_transfer` · `session_merge` · `session_split` · `session_upgrade_plan` · `session_emergency_stop` · `unbilled_sessions`

---

## G. Bookings

`booking_create` · `booking_reschedule` · `booking_cancel` · `booking_checkin` · `waitlist_join` · `waitlist_offer` · `booking_calendar`

---

## H. Members / CRM

`member_search` · `member_get` · `member_create` · `member_update` · `member_block` · `member_stats_get` · `member_timeline` · `member_note_add` · `member_document_add`

---

## I. Memberships / loyalty / wallet

`membership_plan_*` · `membership_subscribe` · `membership_renew` · `membership_cancel` · `loyalty_balance` · `loyalty_adjust` · `wallet_topup` · `wallet_transfer` · `wallet_pay` · `coupon_redeem` · `gift_card_*`

---

## J. Pricing

`billing_plan_*` · `pricing_rule_*` · `happy_hour_*`

---

## K. Inventory / POS extras

`product_*` · `inventory_receive` · `inventory_adjust` · `inventory_transfer` · `po_*` · `supplier_*` · `order_remove_item` · `order_add_bundle` · `refund_create` · `tip_add`

---

## L. Shift / finance / HR

`shift_open` · `shift_current` · `shift_summary` · `shift_close` · `cash_movement_create` · `expense_*` · `attendance_punch` · `leave_*` · `task_*`

---

## M. Tournaments / events

`tournament_*` · `event_*`

---

## N. Notifications / marketing

`notification_enqueue` · `campaign_*` · `referral_*`

---

## O. Reports

`report_sales` · `report_sessions` · `report_occupancy` · `report_peak_hours` · `report_members` · `report_inventory` · `report_tax` · `report_pnl` · `report_staff` · `export_job_create`

---

## P. AI

`insights_request` · `insights_get` → `not_implemented` unless flag + worker live

---

## Q. Platform (Super Admin)

`platform.tenant_*` · `platform.subscription_*` · `platform.invoice_*` · `platform.flag_*` · `platform.domain_*` · `platform.usage_*` · `platform.impersonate_start` · `platform.impersonate_end`

---

## R. Customer app / portal

Subset of H/I/G + `customer_register` · `availability_get` · `rating_submit` · `support_ticket_create`

---

## Error codes (extend API.md)

Reuse: `insufficient_privilege` · `not_found` · `invalid_state` · `conflict` · `idempotency_key_reuse` · `operation_in_progress` · `validation_failed` · `clock_skew_exceeded` · `stale_operation` · `offline_not_permitted`

Add: `feature_disabled` · `membership_inactive` · `wallet_insufficient` · `booking_conflict` · `agent_unreachable` · `not_implemented`
