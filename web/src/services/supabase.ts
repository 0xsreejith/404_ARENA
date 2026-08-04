import { createClient } from '@supabase/supabase-js';

const metaEnv = (import.meta as unknown as { env?: Record<string, string> }).env || {};
const supabaseUrl = metaEnv.VITE_SUPABASE_URL || 'http://127.0.0.1:54321';
const supabaseAnonKey = metaEnv.VITE_SUPABASE_ANON_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.e30.key';

export const supabase = createClient(supabaseUrl, supabaseAnonKey);

export interface UserProfile {
  id: string;
  display_name: string;
  phone?: string;
}

export interface ArenaBranding {
  brand_name: string;
  logo_url?: string;
  primary_color: string;
  accent_color: string;
}

export interface ArenaRole {
  code: string;
  name: string;
}

export interface ArenaContext {
  id: string;
  name: string;
  timezone: string;
  currency: string;
  branding: ArenaBranding;
  role: ArenaRole;
  permissions: string[];
}

export interface MeResponse {
  user: UserProfile;
  arenas: ArenaContext[];
}

export async function fetchMeContext(): Promise<MeResponse> {
  const { data, error } = await supabase.rpc('me');
  if (error) {
    throw error;
  }
  return data as MeResponse;
}
