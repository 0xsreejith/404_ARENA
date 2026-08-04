import { supabase } from './supabase';

export interface Zone {
  id: string;
  name: string;
  sort_order: number;
}

export interface StationType {
  id: string;
  name: string;
  icon?: string;
  hourly_rate: number;
}

export interface Station {
  id: string;
  name: string;
  zone_id: string;
  station_type_id: string;
  status: 'active' | 'maintenance' | 'inactive';
  status_reason?: string;
  seat_capacity?: number;
}

export interface Game {
  id: string;
  title: string;
  cover_url?: string;
}

export interface BillingPlan {
  id: string;
  name: string;
  type: 'open_time' | 'fixed_duration';
  duration_minutes?: number;
  price: number;
  station_type_id?: string;
}

export interface LiveSession {
  id: string;
  station_id: string;
  member_id?: string;
  member_name?: string;
  game_id?: string;
  game_title?: string;
  billing_plan_id: string;
  status: 'active' | 'paused' | 'completed' | 'cancelled';
  player_count: number;
  started_at: string;
  planned_end_at?: string;
  paused_at?: string;
  total_paused_seconds: number;
  pricing_snapshot: any;
}

export interface UnbilledSession {
  id: string;
  station_id: string;
  station_name: string;
  member_name?: string;
  started_at: string;
  ended_at: string;
  status: string;
  open_order_id?: string;
}

export interface FloorSnapshotResponse {
  zones: Zone[];
  station_types: StationType[];
  stations: Station[];
  games: Game[];
  billing_plans: BillingPlan[];
  live_sessions: LiveSession[];
  unbilled_sessions: UnbilledSession[];
}

export async function fetchFloorSnapshot(arenaId: string): Promise<FloorSnapshotResponse> {
  const { data, error } = await supabase.rpc('floor_snapshot', { p_arena_id: arenaId });
  if (error) throw error;
  return data as FloorSnapshotResponse;
}

export async function startSessionRPC(params: {
  arenaId: string;
  sessionId: string;
  stationId: string;
  billingPlanId: string;
  memberId?: string;
  gameId?: string;
  playerCount?: number;
}) {
  const { data, error } = await supabase.rpc('session_start', {
    p_arena_id: params.arenaId,
    p_session_id: params.sessionId,
    p_station_id: params.stationId,
    p_billing_plan_id: params.billingPlanId,
    p_member_id: params.memberId || null,
    p_game_id: params.gameId || null,
    p_player_count: params.playerCount || 1,
  });
  if (error) throw error;
  return data;
}

export async function pauseSessionRPC(arenaId: string, sessionId: string) {
  const { data, error } = await supabase.rpc('session_pause', {
    p_arena_id: arenaId,
    p_session_id: sessionId,
  });
  if (error) throw error;
  return data;
}

export async function resumeSessionRPC(arenaId: string, sessionId: string) {
  const { data, error } = await supabase.rpc('session_resume', {
    p_arena_id: arenaId,
    p_session_id: sessionId,
  });
  if (error) throw error;
  return data;
}

export async function stopSessionRPC(arenaId: string, sessionId: string) {
  const { data, error } = await supabase.rpc('session_stop', {
    p_arena_id: arenaId,
    p_session_id: sessionId,
  });
  if (error) throw error;
  return data;
}
