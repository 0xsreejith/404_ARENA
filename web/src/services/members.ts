import { supabase } from './supabase';

export interface MemberSearchRow {
  id: string;
  full_name: string;
  phone?: string;
  phone_masked?: string;
  blocked?: boolean;
  blocked_reason?: string | null;
  visit_count?: number;
  total_spend?: string | number;
  last_visit_at?: string | null;
  member_code?: string;
}

export interface MemberRecord {
  id: string;
  full_name: string;
  phone: string;
  phone_masked?: string;
  blocked: boolean;
  blocked_reason?: string | null;
  notes?: string | null;
  member_code?: string;
  outstanding_balance?: string;
  wallet_balance?: string;
  profile?: Record<string, unknown>;
  stats?: {
    visit_count?: number;
    total_spend?: string | number;
    total_hours?: string | number;
    last_visit_at?: string | null;
  };
  tags?: Array<{ id: string; code: string; label: string }>;
  loyalty?: { points?: number; tier?: { code: string; label: string } | null };
  membership?: { plan_name?: string; ends_at?: string; status?: string } | null;
  recent_sessions?: Array<Record<string, unknown>>;
}

export async function searchMembers(
  arenaId: string,
  query: string,
  limit = 20,
): Promise<MemberSearchRow[]> {
  const { data, error } = await supabase.rpc('member_search', {
    p_arena_id: arenaId,
    p_query: query,
    p_limit: limit,
  });
  if (error) throw error;
  const members = (data as { members?: unknown })?.members;
  return Array.isArray(members) ? (members as MemberSearchRow[]) : [];
}

export async function getMember(arenaId: string, memberId: string): Promise<MemberRecord> {
  const { data, error } = await supabase.rpc('member_get', {
    p_arena_id: arenaId,
    p_member_id: memberId,
  });
  if (error) throw error;
  return data as MemberRecord;
}

export async function createMember(params: {
  arenaId: string;
  memberId: string;
  fullName: string;
  phone: string;
  notes?: string;
  idempotencyKey: string;
}): Promise<MemberRecord> {
  const { data, error } = await supabase.rpc('member_create', {
    p_arena_id: params.arenaId,
    p_member_id: params.memberId,
    p_full_name: params.fullName,
    p_phone: params.phone,
    p_dob: null,
    p_notes: params.notes ?? null,
    p_idempotency_key: params.idempotencyKey,
  });
  if (error) throw error;
  return data as MemberRecord;
}

export async function setMemberBlocked(params: {
  arenaId: string;
  memberId: string;
  blocked: boolean;
  reason?: string;
}): Promise<MemberRecord> {
  const { data, error } = await supabase.rpc('member_set_blocked', {
    p_arena_id: params.arenaId,
    p_member_id: params.memberId,
    p_blocked: params.blocked,
    p_reason: params.reason ?? null,
  });
  if (error) throw error;
  return data as MemberRecord;
}

export async function fetchMemberAnalytics(arenaId: string) {
  const { data, error } = await supabase.rpc('member_analytics_overview', {
    p_arena_id: arenaId,
  });
  if (error) throw error;
  return data as {
    counts?: Record<string, number>;
    top_spend?: MemberSearchRow[];
    no_visit_90d?: MemberSearchRow[];
  };
}

export async function listMembershipPlans(arenaId: string) {
  const { data, error } = await supabase.rpc('membership_plan_list', {
    p_arena_id: arenaId,
  });
  if (error) throw error;
  const plans = (data as { plans?: unknown })?.plans;
  return Array.isArray(plans) ? plans : [];
}

export async function walletTopup(params: {
  arenaId: string;
  memberId: string;
  amount: string;
  note?: string;
}) {
  const { data, error } = await supabase.rpc('wallet_topup', {
    p_arena_id: params.arenaId,
    p_member_id: params.memberId,
    p_amount: params.amount,
    p_note: params.note ?? null,
  });
  if (error) throw error;
  return data;
}

export function readableMemberError(err: unknown, fallback: string): string {
  const message =
    err && typeof err === 'object' && 'message' in err
      ? String((err as { message: unknown }).message)
      : fallback;
  return message;
}
