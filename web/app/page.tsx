'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { useSession } from '../lib/session';

/** Nothing lives at the root — send each role to its own console. */
export default function Home() {
  const { me, loading } = useSession();
  const router = useRouter();

  useEffect(() => {
    if (loading) return;
    if (!me) router.replace('/login');
    else if (me.user.role === 'doctor') router.replace('/doctor');
    else if (me.user.role === 'admin') router.replace('/admin');
  }, [loading, me, router]);

  if (!loading && me && me.user.role === 'patient') {
    return (
      <div className="panel">
        <h1>This console is for hospital staff</h1>
        <p className="muted">
          Patient accounts use the mobile app. Sign out and use a doctor or hospital admin
          account to continue.
        </p>
      </div>
    );
  }
  return <p className="muted">Loading…</p>;
}
