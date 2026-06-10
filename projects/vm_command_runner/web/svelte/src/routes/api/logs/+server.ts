import type { RequestHandler } from './$types';
import { json } from '@sveltejs/kit';
import { callFunction } from '$lib/server/functionClient';

export const GET: RequestHandler = async ({ url }) => {
  const limit = url.searchParams.get('limit') ?? '50';
  const res = await callFunction('/api/logs', { query: { limit } });
  return json(res.data, { status: res.status });
};
