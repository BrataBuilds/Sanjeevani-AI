'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useSession } from '../lib/session';

const DOCTOR_LINKS = [
  ['/doctor', 'Queue'],
  ['/doctor/messages', 'Messages'],
] as const;

const ADMIN_LINKS = [
  ['/admin', 'Dashboard'],
  ['/admin/visits', 'Visits'],
  ['/admin/doctors', 'Doctors'],
  ['/admin/audit', 'Audit'],
] as const;

export function TopBar() {
  const { me, signOut } = useSession();
  const pathname = usePathname();
  const links = me?.user.role === 'doctor' ? DOCTOR_LINKS : me?.user.role === 'admin' ? ADMIN_LINKS : [];

  return (
    <header className="topbar">
      <span className="brand">
        <span className="mark">S</span>
        Sanjeevani
      </span>
      {links.length > 0 && (
        <nav>
          {links.map(([href, label]) => (
            <Link
              key={href}
              href={href}
              className={pathname === href || pathname.startsWith(`${href}/`) ? 'active' : undefined}
            >
              {label}
            </Link>
          ))}
        </nav>
      )}
      <span className="spacer" />
      {me && (
        <div className="who">
          <span className="small" style={{ fontWeight: 600 }}>
            {me.user.full_name}
          </span>
          <span className="small muted">
            {me.user.role}
            {me.doctor?.hospital_name ? ` · ${me.doctor.hospital_name}` : ''}
            {me.admin?.hospital_name ? ` · ${me.admin.hospital_name}` : ''}
          </span>
          <button className="secondary" onClick={signOut}>
            Sign out
          </button>
        </div>
      )}
    </header>
  );
}
