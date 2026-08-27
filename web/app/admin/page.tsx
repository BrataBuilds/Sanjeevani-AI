'use client';

import { useCallback, useState } from 'react';
import { api } from '../../lib/api';
import { RequireRole, usePolling } from '../../lib/session';
import { Bars, Pills, Stat, Urgency } from '../ui';

type Overview = {
  window_days: number;
  totals: { today: number; in_queue: number; critical_today: number; all_time: number };
  staff: { doctors: number; available: number };
  avg_handling_minutes: number | null;
  by_status: { status: string; n: number }[];
  by_urgency: { urgency: number; n: number }[];
  by_department: { department: string; n: number; waiting: number }[];
  by_specialty: { specialty: string; n: number }[];
  daily: { day: string; n: number; urgent: number }[];
};

export default function AdminPage() {
  return (
    <RequireRole role="admin">
      <Overview />
    </RequireRole>
  );
}

function Overview() {
  const [days, setDays] = useState('7');
  const load = useCallback(() => api<Overview>(`/admin/overview?days=${days}`), [days]);
  const { data, error, pending } = usePolling(load, 30000);

  if (error) return <p className="error">{error}</p>;
  if (pending && !data) return <p className="muted">Loading…</p>;
  if (!data) return null;

  return (
    <>
      <h1>Patient flow</h1>
      <p className="muted small">Refreshes every 30 seconds.</p>

      <div className="grid">
        <Stat n={data.totals.today} k="Registered today" />
        <Stat n={data.totals.in_queue} k="Currently in queue" />
        <Stat n={data.totals.critical_today} k="Urgency 1 today" tone="danger" />
        <Stat n={`${data.staff.available}/${data.staff.doctors}`} k="Doctors available" />
        <Stat n={data.avg_handling_minutes} k="Avg minutes to close" tone="warn" />
        <Stat n={data.totals.all_time} k="Visits all time" />
      </div>

      <Pills
        value={days}
        onChange={setDays}
        options={[
          { value: '7', label: 'Last 7 days' },
          { value: '14', label: 'Last 14 days' },
          { value: '30', label: 'Last 30 days' },
        ]}
      />
      <div style={{ marginBottom: 14 }} />

      <div className="cols2">
        <div className="panel">
          <h2 style={{ marginTop: 0 }}>Department load (today)</h2>
          <Bars
            rows={data.by_department.map((d) => ({
              label: d.department,
              value: d.n,
              sub: `${d.n} total · ${d.waiting} waiting`,
            }))}
          />

          <h2>Routed specialty (last {data.window_days} days)</h2>
          <Bars rows={data.by_specialty.map((s) => ({ label: s.specialty, value: s.n }))} />

          <h2>Daily volume</h2>
          <Bars
            rows={data.daily.map((d) => ({
              label: d.day,
              value: d.n,
              sub: `${d.n} visits · ${d.urgent} urgent`,
            }))}
          />
        </div>

        <div className="panel">
          <h2 style={{ marginTop: 0 }}>Status (today)</h2>
          {data.by_status.length === 0 && <p className="muted small">Nothing today yet.</p>}
          <table>
            <tbody>
              {data.by_status.map((s) => (
                <tr key={s.status}>
                  <td>{s.status.replace('_', ' ')}</td>
                  <td style={{ textAlign: 'right' }}>{s.n}</td>
                </tr>
              ))}
            </tbody>
          </table>

          <h2>Urgency mix (today)</h2>
          <table>
            <tbody>
              {data.by_urgency.map((u) => (
                <tr key={u.urgency}>
                  <td>
                    <Urgency value={u.urgency} />
                  </td>
                  <td style={{ textAlign: 'right' }}>{u.n}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </>
  );
}
