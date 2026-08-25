'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { api, setToken } from '../../lib/api';
import { useSession } from '../../lib/session';

/**
 * Email + password only. Doctors and hospital admins are provisioned by an admin
 * (POST /admin/doctors) and never self-signup, so there is no register form and
 * no Google button here — that path belongs to the patient app.
 */
export default function LoginPage() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const { me, reload } = useSession();
  const router = useRouter();

  useEffect(() => {
    if (me?.user.role === 'doctor') router.replace('/doctor');
    if (me?.user.role === 'admin') router.replace('/admin');
  }, [me, router]);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const out = await api<{ token: string; user: { role: string } }>('/auth/login', {
        method: 'POST',
        body: { email, password },
      });
      if (out.user.role === 'patient') {
        setError('This console is for hospital staff. Patient accounts use the mobile app.');
        return;
      }
      setToken(out.token);
      await reload();
      router.replace(out.user.role === 'admin' ? '/admin' : '/doctor');
    } catch (err: any) {
      setError(err?.message ?? 'sign in failed');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="login-shell">
      <div className="panel">
        <h1>Staff sign in</h1>
        <p className="muted small">Doctor and hospital admin console.</p>
        <form onSubmit={submit}>
          <label htmlFor="email">Email</label>
          <input
            id="email"
            type="email"
            autoComplete="username"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            required
          />
          <label htmlFor="password" style={{ marginTop: 10 }}>
            Password
          </label>
          <input
            id="password"
            type="password"
            autoComplete="current-password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
          />
          {error && (
            <p className="error small" role="alert">
              {error}
            </p>
          )}
          <button type="submit" disabled={busy} style={{ marginTop: 14 }}>
            {busy ? 'Signing in…' : 'Sign in'}
          </button>
        </form>
      </div>
      <p className="muted small">
        Seeded demo accounts: <code>dr.mehta@citygeneral.test</code> (doctor) and{' '}
        <code>admin@citygeneral.test</code> (admin), password <code>password123</code>.
      </p>
    </div>
  );
}
