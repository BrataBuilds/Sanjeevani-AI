'use client';

import { createContext, useCallback, useContext, useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { api, clearToken, getToken } from './api';

type Me = {
  user: { id: string; email: string; role: 'patient' | 'doctor' | 'admin'; full_name: string };
  doctor?: { hospital_name?: string; department_name?: string; specialty?: string };
  admin?: { hospital_name?: string };
};

type Session = {
  me: Me | null;
  loading: boolean;
  reload: () => Promise<void>;
  signOut: () => void;
};

const Ctx = createContext<Session>({ me: null, loading: true, reload: async () => {}, signOut: () => {} });

export function SessionProvider({ children }: { children: React.ReactNode }) {
  const [me, setMe] = useState<Me | null>(null);
  const [loading, setLoading] = useState(true);
  const router = useRouter();

  const reload = useCallback(async () => {
    if (!getToken()) {
      setMe(null);
      setLoading(false);
      return;
    }
    try {
      setMe(await api<Me>('/auth/me'));
    } catch {
      clearToken();
      setMe(null);
    } finally {
      setLoading(false);
    }
  }, []);

  const signOut = useCallback(() => {
    clearToken();
    setMe(null);
    router.push('/login');
  }, [router]);

  useEffect(() => {
    reload();
  }, [reload]);

  return <Ctx.Provider value={{ me, loading, reload, signOut }}>{children}</Ctx.Provider>;
}

export const useSession = () => useContext(Ctx);

/** Wrap a page body in this to keep the wrong role (or nobody) out. */
export function RequireRole({
  role,
  children,
}: {
  role: 'doctor' | 'admin';
  children: React.ReactNode;
}) {
  const { me, loading } = useSession();
  const router = useRouter();

  useEffect(() => {
    if (loading) return;
    if (!me) router.replace('/login');
    else if (me.user.role !== role) router.replace('/');
  }, [loading, me, role, router]);

  if (loading) return <p className="muted">Loading…</p>;
  if (!me || me.user.role !== role) return null;
  return <>{children}</>;
}

/** Poll a loader on an interval. The API has no push channel by design. */
export function usePolling<T>(load: () => Promise<T>, ms = 10000) {
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(true);

  const run = useCallback(async () => {
    try {
      setData(await load());
      setError(null);
    } catch (err: any) {
      setError(err?.message ?? 'request failed');
    } finally {
      setPending(false);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [load]);

  useEffect(() => {
    run();
    if (!ms) return;
    const id = setInterval(run, ms);
    return () => clearInterval(id);
  }, [run, ms]);

  return { data, error, pending, refresh: run };
}
