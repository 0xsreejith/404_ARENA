import { supabase } from './supabase';

export interface ShiftRecord {
  id: string;
  arena_id: string;
  business_date: string;
  status: 'open' | 'closed';
  opened_by_user_id: string;
  opened_at: string;
  opening_float: string;
  closed_by_user_id?: string;
  closed_at?: string;
  expected_cash?: string;
  counted_cash?: string;
  variance?: string;
  notes?: string;
}

export interface ShiftSummary {
  shift_id: string;
  status: 'open' | 'closed';
  business_date: string;
  opened_at: string;
  closed_at?: string;
  opening_float: string;
  order_count: number;
  session_count: number;
  sales: {
    play?: string;
    product?: string;
  };
  discount_total: string;
  tax_total: string;
  payments_by_method: {
    cash?: string;
    upi?: string;
    card?: string;
  };
  cash_payments: string;
  expected_cash: string;
  unbilled_session_count: number;
}

export async function fetchCurrentShift(arenaId: string): Promise<ShiftRecord | null> {
  const { data, error } = await supabase.rpc('shift_current', { p_arena_id: arenaId });
  if (error) throw error;
  return data as ShiftRecord | null;
}

export async function openShift(params: {
  arenaId: string;
  shiftId: string;
  openingFloat: string;
  idempotencyKey: string;
}): Promise<ShiftRecord> {
  const { data, error } = await supabase.rpc('shift_open', {
    p_arena_id: params.arenaId,
    p_shift_id: params.shiftId,
    p_opening_float: params.openingFloat,
    p_idempotency_key: params.idempotencyKey,
  });
  if (error) throw error;
  return data as ShiftRecord;
}

export async function fetchShiftSummary(arenaId: string, shiftId: string): Promise<ShiftSummary> {
  const { data, error } = await supabase.rpc('shift_summary', {
    p_arena_id: arenaId,
    p_shift_id: shiftId,
  });
  if (error) throw error;
  return data as ShiftSummary;
}

export async function closeShift(params: {
  arenaId: string;
  shiftId: string;
  countedCash: string;
  notes: string;
  idempotencyKey: string;
}): Promise<ShiftRecord> {
  const { data, error } = await supabase.rpc('shift_close', {
    p_arena_id: params.arenaId,
    p_shift_id: params.shiftId,
    p_counted_cash: params.countedCash,
    p_notes: params.notes,
    p_idempotency_key: params.idempotencyKey,
  });
  if (error) throw error;
  return data as ShiftRecord;
}

export function readableShiftError(err: unknown, fallback: string): string {
  const message =
    err && typeof err === 'object' && 'message' in err
      ? String((err as { message: unknown }).message)
      : fallback;
  if (message.toLowerCase().includes('open shift')) {
    return 'Open a shift before taking payments.';
  }
  return message;
}
