'use client';

/**
 * Thin fetch wrapper. The backend is token-based (no cookies), so the JWT lives
 * in localStorage and every page is a client component. Deliberately small — the
 * design team is expected to replace the UI, not this file.
 */

export const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:4000';

const TOKEN_KEY = 'sanjeevani.token';

export const getToken = () =>
  typeof window === 'undefined' ? null : window.localStorage.getItem(TOKEN_KEY);
export const setToken = (t: string) => window.localStorage.setItem(TOKEN_KEY, t);
export const clearToken = () => window.localStorage.removeItem(TOKEN_KEY);

export class ApiError extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

type Options = { method?: string; body?: unknown; signal?: AbortSignal };

export async function api<T = any>(path: string, opts: Options = {}): Promise<T> {
  const token = getToken();
  const res = await fetch(`${API_URL}${path}`, {
    method: opts.method ?? 'GET',
    signal: opts.signal,
    headers: {
      ...(opts.body !== undefined ? { 'content-type': 'application/json' } : {}),
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: opts.body !== undefined ? JSON.stringify(opts.body) : undefined,
    cache: 'no-store',
  });

  const text = await res.text();
  let data: any = null;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    data = { error: text.slice(0, 300) };
  }
  if (!res.ok) throw new ApiError(res.status, data?.error || res.statusText);
  return data as T;
}

/**
 * Stored files need the Authorization header, so an <img src> pointing at the API
 * would 401. Fetch the bytes and hand back an object URL instead.
 */
export async function fetchBlobUrl(path: string): Promise<string> {
  const token = getToken();
  const res = await fetch(`${API_URL}${path}`, {
    headers: token ? { authorization: `Bearer ${token}` } : {},
  });
  if (!res.ok) throw new ApiError(res.status, `could not load ${path}`);
  return URL.createObjectURL(await res.blob());
}

export const URGENCY_LABEL: Record<number, string> = {
  1: '1 · immediate',
  2: '2 · very urgent',
  3: '3 · urgent',
  4: '4 · standard',
  5: '5 · non-urgent',
};

export const fmtTime = (iso?: string | null) =>
  iso ? new Date(iso).toLocaleString() : '—';

export const waitedMinutes = (iso?: string | null) =>
  iso ? Math.max(0, Math.round((Date.now() - new Date(iso).getTime()) / 60000)) : 0;
