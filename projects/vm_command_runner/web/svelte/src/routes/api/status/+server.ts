import type { RequestHandler } from './$types';
import { json } from '@sveltejs/kit';
import { callFunction } from '$lib/server/functionClient';

export const GET: RequestHandler = async () => {
  const res = await callFunction('/api/status');
  return json(res.data, { status: res.status });
};
