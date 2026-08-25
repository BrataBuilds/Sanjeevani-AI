'use client';

import { useCallback } from 'react';
import Link from 'next/link';
import { api, fmtTime } from '../../../lib/api';
import { RequireRole, usePolling } from '../../../lib/session';

type Row = {
  id: string;
  kind: string;
  title: string | null;
  patient_name: string;
  last_message: string | null;
  last_message_at: string;
};

export default function MessagesPage() {
  return (
    <RequireRole role="doctor">
      <List />
    </RequireRole>
  );
}

function List() {
  const load = useCallback(() => api<Row[]>('/conversations'), []);
  const { data, error, pending } = usePolling(load, 15000);

  return (
    <>
      <h1>Messages</h1>
      <p className="muted small">Care-team threads with patients at your hospital.</p>
      {error && <p className="error">{error}</p>}
      {pending && !data && <p className="muted">Loading…</p>}
      {data && data.length === 0 && (
        <p className="muted">
          No threads yet. Open one from a visit with the “Message patient” button.
        </p>
      )}
      {data && data.length > 0 && (
        <div className="table-scroll">
          <table>
            <thead>
              <tr>
                <th>Patient</th>
                <th>Last message</th>
                <th>When</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {data.map((c) => (
                <tr key={c.id}>
                  <td>{c.patient_name}</td>
                  <td className="small">{c.last_message ?? '—'}</td>
                  <td className="small">{fmtTime(c.last_message_at)}</td>
                  <td>
                    <Link href={`/doctor/conversations/${c.id}`}>Open</Link>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </>
  );
}
