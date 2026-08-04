-- Migration: 20260804140000_epic4_auth_context.sql
-- Description: Epic 4 / M2 — align devices.platform CHECK with register_device
--              (android|ios|web|desktop). No new public RPCs.
-- Authoritative Spec: docs/API.md §2 · docs/ROADMAP.md M2 · IMPLEMENTATION_PLAN Epic 4

alter table public.devices
  drop constraint if exists devices_platform_check;

alter table public.devices
  add constraint devices_platform_check
  check (platform in ('android', 'ios', 'web', 'desktop'));

comment on column public.devices.platform is
  'Client platform for telemetry. Includes web/desktop for Owner Web and '
  'desktop shells; register_device validates the same set.';
