import type { PageServerLoad } from './$types';
import { callFunction } from '$lib/server/functionClient';

interface StatusPayload {
  vm_name: string;
  power_state: string;
  last_access_utc: string | null;
  idle_minutes_threshold: number;
  allowed_commands: string[];
}

export const load: PageServerLoad = async () => {
  const res = await callFunction<StatusPayload>('/api/status');
  return {
    status: res.ok ? res.data as StatusPayload : null,
    statusError: res.ok ? null : (res.data as { error: string }).error ?? `HTTP ${res.status}`
  };
};
