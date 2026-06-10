import type { RequestHandler } from './$types';
import { json } from '@sveltejs/kit';
import { callFunction } from '$lib/server/functionClient';

export const POST: RequestHandler = async () => {
  const res = await callFunction('/api/start', { method: 'POST' });
  return json(res.data, { status: res.status });
};
