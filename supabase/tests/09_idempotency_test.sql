-- M1 — the server-side idempotency store.
--
-- This is not the client outbox: that lives only in Drift on the device and is
-- never synchronised here (D16).
--
-- Covers SECURITY.md §15 assertion 11 and the DATABASE.md §11 contract.

begin;
set local search_path to extensions, public, pg_catalog;

\ir fixtures/two_tenants.psql

select plan(11);

select pg_temp.become(:'user_a_owner');

-- ── Miss, then completion, then replay ───────────────────────────────────────

select is(
  app.claim_idempotency(:'arena_a'::uuid, 'key-1', 'session_start', 'fingerprint-1'),
  null,
  'a first claim returns SQL NULL, meaning the caller proceeds (DATABASE.md §11 step 2)'
);

select is(
  (select status from public.idempotency_keys
    where arena_id = :'arena_a' and key = 'key-1'),
  'in_progress',
  'the claim is recorded as in_progress while the operation runs'
);

select lives_ok(
  format(
    $$ select app.complete_idempotency(%L, 'key-1', '{"session_id": "abc"}'::jsonb) $$,
    :'arena_a'
  ),
  'the RPC stores its authoritative response against the key (SECURITY.md §5 step 8)'
);

select is(
  app.claim_idempotency(:'arena_a'::uuid, 'key-1', 'session_start', 'fingerprint-1'),
  '{"session_id": "abc"}'::jsonb,
  'a replay with the same key and the same arguments returns the STORED response, '
  'not a repeated side effect (assertion 11)'
);

select is(
  (select count(*) from public.idempotency_keys
    where arena_id = :'arena_a' and key = 'key-1')::int,
  1,
  'replaying does not create a second claim'
);

-- ── Same key, different arguments ────────────────────────────────────────────

select throws_like(
  format(
    $$ select app.claim_idempotency(%L, 'key-1', 'session_start', 'fingerprint-2') $$,
    :'arena_a'
  ),
  'idempotency_key_reuse:%',
  'the same key with different arguments is a conflict (assertion 11)'
);

select throws_like(
  format(
    $$ select app.claim_idempotency(%L, 'key-1', 'session_stop', 'fingerprint-1') $$,
    :'arena_a'
  ),
  'idempotency_key_reuse:%',
  'the same key reused for a different operation is a conflict'
);

-- ── A claim still in flight ──────────────────────────────────────────────────

select throws_like(
  format(
    $$ select app.claim_idempotency(%L, %L, 'session_start', 'a-different-fingerprint') $$,
    :'arena_a', 'a-seed-key'
  ),
  'idempotency_key_reuse:%',
  'the fingerprint is checked before the status, so a mismatched replay of an '
  'already-succeeded key conflicts rather than returning its response'
);

update public.idempotency_keys set status = 'in_progress'
 where arena_id = :'arena_a' and key = 'key-1';

select throws_like(
  format(
    $$ select app.claim_idempotency(%L, 'key-1', 'session_start', 'fingerprint-1') $$,
    :'arena_a'
  ),
  'operation_in_progress:%',
  'a concurrent call under the same key is retryable, not a duplicate'
);

-- ── A rejected attempt may be retried under the same key (OFFLINE.md §5) ─────

update public.idempotency_keys set status = 'failed'
 where arena_id = :'arena_a' and key = 'key-1';

select is(
  app.claim_idempotency(:'arena_a'::uuid, 'key-1', 'session_start', 'fingerprint-1'),
  null,
  'a failed claim with a matching fingerprint re-opens rather than conflicting'
);

-- ── Keys are namespaced per arena (D16) ──────────────────────────────────────

select pg_temp.become(:'user_b_owner');

select is(
  app.claim_idempotency(:'arena_b'::uuid, 'key-1', 'session_start', 'something-else'),
  null,
  'the same key in another arena is a miss: a key from one tenant can never '
  'match another''s'
);

select * from finish();
rollback;
