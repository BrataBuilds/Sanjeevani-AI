'use client';

import Link from 'next/link';
import { useSession } from '../lib/session';

export function TopBar() {
  const { me, signOut } = useSession();

  return (
    <header className="topbar">
      <span className="brand">Sanjeevani AI</span>
      {me?.user.role === 'doctor' && (
        <nav>
          <Link href="/doctor">Queue</Link>
          <Link href="/doctor/messages">Messages</Link>
        </nav>
      )}
      {me?.user.role === 'admin' && (
        <nav>
          <Link href="/admin">Overview</Link>
          <Link href="/admin/visits">Visits</Link>
          <Link href="/admin/doctors">Doctors</Link>
          <Link href="/admin/audit">Audit</Link>
        </nav>
      )}
      <span className="spacer" />
      {me && (
        <>
          <span className="small muted">
            {me.user.full_name} · {me.user.role}
            {me.doctor?.hospital_name ? ` · ${me.doctor.hospital_name}` : ''}
            {me.admin?.hospital_name ? ` · ${me.admin.hospital_name}` : ''}
          </span>
          <button className="secondary" onClick={signOut}>
            Sign out
          </button>
        </>
      )}
    </header>
  );
}
