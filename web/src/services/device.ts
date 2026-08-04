import { supabase } from './supabase';

const DEVICE_ID_KEY = 'arena_os.device_id';

function newUuidV4(): string {
  if (typeof crypto !== 'undefined' && 'randomUUID' in crypto) {
    return crypto.randomUUID();
  }
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === 'x' ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

export function loadOrCreateDeviceId(): string {
  const existing = localStorage.getItem(DEVICE_ID_KEY);
  if (existing) return existing;
  const id = newUuidV4();
  localStorage.setItem(DEVICE_ID_KEY, id);
  return id;
}

/** Telemetry only — requires station.view; never blocks arena entry. */
export async function registerDevice(arenaId: string, deviceName = 'Owner Web'): Promise<void> {
  const deviceId = loadOrCreateDeviceId();
  const { error } = await supabase.rpc('register_device', {
    p_arena_id: arenaId,
    p_device_id: deviceId,
    p_name: deviceName,
    p_platform: 'web',
    p_app_version: '0.1.0',
  });
  if (error) throw error;
}

export function mapAuthError(err: unknown): string {
  const message =
    err && typeof err === 'object' && 'message' in err
      ? String((err as { message: unknown }).message)
      : String(err ?? 'Authentication failed');
  const lower = message.toLowerCase();
  if (lower.includes('invalid') || lower.includes('credentials')) {
    return 'Email or password is incorrect.';
  }
  return message;
}
