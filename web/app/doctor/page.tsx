'use client';

import { useCallback, useState } from 'react';
import Link from 'next/link';
import { api, fmtTime, waitedMinutes } from '../../lib/api';
import { RequireRole, usePolling } from '../../lib/session';
import { Status, Urgency } from '../ui';

type QueueRow = {
  id: string;
  token_no: number;
  status: string;
  urgency: number;
  urgency_overridden: boolean;
  reason: string | null;
  created_at: string;
  patient_id: string;
  patient_name: string;
  age: number | null;
  gender: string | null;
  department_name: string | null;
  doctor_name: string | null;
  specialty: string | null;
  red_flag: boolean | null;
  chief_complaint: string | null;
};

export default function DoctorQueuePage() {
  return (
    <RequireRole role="doctor">
      <Queue />
    </RequireRole>
  );
}

function Queue() {
  const [scope, setScope] = useState<'mine' | 'department' | 'hospital'>('mine');
  const [status, setStatus] = useState('');

  const load = useCallback(
    () =>
      api<QueueRow[]>(
        `/doctor/queue?scope=${scope}${status ? `&status=${status}` : ''}`,
      ),
    [scope, status],
  );
  const { data, error, pending, refresh } = usePolling(load, 15000);

  return (
    <>
      <h1>Queue</h1>
      <p className="muted small">
        Most urgent first, then longest waiting. Refreshes every 15 seconds.
      </p>

      <div className="panel row">
        <div>
          <label htmlFor="scope">Scope</label>
          <select id="scope" value={scope} onChange={(e) => setScope(e.target.value as any)}>
            <option value="mine">Assigned to me</option>
            <option value="department">My department</option>
            <option value="hospital">Whole hospital</option>
          </select>
        </div>
        <div>
          <label htmlFor="status">Status</label>
          <select id="status" value={status} onChange={(e) => setStatus(e.target.value)}>
            <option value="">All (today)</option>
            <option value="waiting">Waiting</option>
            <option value="in_consult">In consult</option>
            <option value="done">Done</option>
            <option value="referred">Referred</option>
          </select>
        </div>
        <button className="secondary" onClick={refresh}>
          Refresh
        </button>
      </div>

      {error && <p className="error">{error}</p>}
      {pending && !data && <p className="muted">Loading…</p>}

      {data && data.length === 0 && <p className="muted">Nothing in this queue right now.</p>}

      {data && data.length > 0 && (
        <div className="table-scroll">
          <table>
            <thead>
              <tr>
                <th>Token</th>
                <th>Urgency</th>
                <th>Patient</th>
                <th>Suggested specialty</th>
                <th>Complaint</th>
                <th>Waiting</th>
                <th>Status</th>
                <th>Assigned</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {data.map((v) => (
                <tr key={v.id}>
                  <td>#{v.token_no}</td>
                  <td>
                    <Urgency value={v.urgency} overridden={v.urgency_overridden} />
                    {v.red_flag && (
                      <>
                        {' '}
                        <span className="tag u1">red flag</span>
                      </>
                    )}
                  </td>
                  <td>
                    {v.patient_name}
                    <div className="small muted">
                      {[v.age !== null ? `${v.age}y` : null, v.gender].filter(Boolean).join(' · ')}
                    </div>
                  </td>
                  <td>
                    {v.specialty ?? <span className="muted">not routed</span>}
                    <div className="small muted">{v.department_name ?? 'no department'}</div>
                  </td>
                  <td className="small">{v.chief_complaint || v.reason || '—'}</td>
                  <td className="small" title={fmtTime(v.created_at)}>
                    {waitedMinutes(v.created_at)} min
                  </td>
                  <td>
                    <Status value={v.status} />
                  </td>
                  <td className="small">{v.doctor_name ?? <span className="muted">unassigned</span>}</td>
                  <td>
                    <Link href={`/doctor/visits/${v.id}`}>Open</Link>
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
