'use client';

import { useCallback, useState } from 'react';
import { api, fmtTime } from '../../../lib/api';
import { RequireRole, usePolling } from '../../../lib/session';
import { Status, Urgency } from '../../ui';

type Row = {
  id: string;
  token_no: number;
  token_date: string;
  status: string;
  urgency: number;
  urgency_overridden: boolean;
  reason: string | null;
  created_at: string;
  patient_name: string;
  age: number | null;
  department_name: string | null;
  doctor_name: string | null;
  specialty: string | null;
  red_flag: boolean | null;
};

export default function AdminVisitsPage() {
  return (
    <RequireRole role="admin">
      <Visits />
    </RequireRole>
  );
}

function Visits() {
  const [status, setStatus] = useState('');
  const load = useCallback(
    () => api<Row[]>(`/admin/visits${status ? `?status=${status}` : ''}`),
    [status],
  );
  const { data, error, pending, refresh } = usePolling(load, 30000);

  return (
    <>
      <h1>Visits</h1>
      <p className="muted small">
        Everything registered at your hospital, newest day first. An ✎ on the urgency means a
        doctor overrode the triage suggestion.
      </p>

      <div className="panel row">
        <div>
          <label htmlFor="status">Status</label>
          <select id="status" value={status} onChange={(e) => setStatus(e.target.value)}>
            <option value="">All</option>
            <option value="waiting">Waiting</option>
            <option value="in_consult">In consult</option>
            <option value="done">Done</option>
            <option value="referred">Referred</option>
            <option value="cancelled">Cancelled</option>
          </select>
        </div>
        <button className="secondary" onClick={refresh}>
          Refresh
        </button>
      </div>

      {error && <p className="error">{error}</p>}
      {pending && !data && <p className="muted">Loading…</p>}
      {data && (
        <div className="table-scroll">
          <table>
            <thead>
              <tr>
                <th>Date</th>
                <th>Token</th>
                <th>Urgency</th>
                <th>Patient</th>
                <th>Specialty</th>
                <th>Department</th>
                <th>Doctor</th>
                <th>Status</th>
                <th>Registered</th>
              </tr>
            </thead>
            <tbody>
              {data.map((v) => (
                <tr key={v.id} className={v.red_flag ? 'row-danger' : v.urgency_overridden ? 'row-diverged' : undefined}>
                  <td className="small">{v.token_date}</td>
                  <td>#{v.token_no}</td>
                  <td>
                    <Urgency value={v.urgency} overridden={v.urgency_overridden} />
                    {v.red_flag && <span className="tag u1"> red flag</span>}
                  </td>
                  <td>
                    {v.patient_name}
                    {v.age !== null && <span className="small muted"> · {v.age}y</span>}
                  </td>
                  <td className="small">{v.specialty ?? '—'}</td>
                  <td className="small">{v.department_name ?? '—'}</td>
                  <td className="small">{v.doctor_name ?? '—'}</td>
                  <td>
                    <Status value={v.status} />
                  </td>
                  <td className="small">{fmtTime(v.created_at)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </>
  );
}
