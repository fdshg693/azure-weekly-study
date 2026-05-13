import type { RequestHandler } from './$types';
import { json } from '@sveltejs/kit';
import { callFunction } from '$lib/server/functionClient';

export const POST: RequestHandler = async ({ request }) => {
  const body = await request.json().catch(() => null);
  const res = await callFunction('/api/run', { method: 'POST', body });
  return json(res.data, { status: res.status });
};
