'use client';

import { useCallback, useEffect, useState } from 'react';
import { api, fmtTime } from '../../../lib/api';
import { RequireRole, usePolling } from '../../../lib/session';
import { Pills, Status, Urgency } from '../../ui';

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
  department_id: string | null;
  doctor_user_id: string | null;
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

type Department = { id: string; name: string };
type Doctor = { user_id: string; full_name: string; department_id: string | null };

function Visits() {
  const [status, setStatus] = useState('');
  const [divFilter, setDivFilter] = useState<'all' | 'agreed' | 'diverged'>('all');
  const [departments, setDepartments] = useState<Department[]>([]);
  const [doctors, setDoctors] = useState<Doctor[]>([]);
  const [assignments, setAssignments] = useState<Record<string, { department_id: string; doctor_user_id: string }>>({});
  const [saving, setSaving] = useState<string | null>(null);
  const load = useCallback(
    () => api<Row[]>(`/admin/visits${status ? `?status=${status}` : ''}`),
    [status],
  );
  const { data, error, pending, refresh } = usePolling(load, 30000);
  useEffect(() => {
    Promise.all([api<Department[]>('/admin/departments'), api<Doctor[]>('/admin/doctors')])
      .then(([dept, doc]) => { setDepartments(dept); setDoctors(doc); })
      .catch(() => {});
  }, []);
  const rows = data?.filter((v) =>
    divFilter === 'all' ? true : divFilter === 'diverged' ? v.urgency_overridden : !v.urgency_overridden,
  );

  async function saveAssignment(row: Row) {
    const value = assignments[row.id] ?? {
      department_id: row.department_id ?? '',
      doctor_user_id: row.doctor_user_id ?? '',
    };
    if (!value.department_id || !value.doctor_user_id) return;
    setSaving(row.id);
    try {
      await api(`/admin/visits/${row.id}/assignment`, { method: 'PATCH', body: value });
      await refresh();
    } finally {
      setSaving(null);
    }
  }

  return (
    <>
      <h1>Visits</h1>
      <p className="muted small">
        Everything registered at your hospital, newest day first. An ✎ on the urgency means a
        doctor overrode the triage suggestion.
      </p>

      <div className="row" style={{ marginBottom: 14, alignItems: 'center' }}>
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
        <Pills
          value={divFilter}
          onChange={setDivFilter}
          options={[
            { value: 'all', label: 'All' },
            { value: 'agreed', label: 'AI accepted' },
            { value: 'diverged', label: 'Overridden' },
          ]}
        />
        <button className="secondary" onClick={refresh}>
          Refresh
        </button>
      </div>

      {error && <p className="error">{error}</p>}
      {pending && !data && <p className="muted">Loading…</p>}
      {rows && (
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
                <th>Reassign</th>
                <th>Status</th>
                <th>Registered</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((v) => (
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
                    <select
                      value={assignments[v.id]?.department_id ?? v.department_id ?? ''}
                      onChange={(e) => setAssignments((all) => ({
                        ...all,
                        [v.id]: {
                          department_id: e.target.value,
                          doctor_user_id: assignments[v.id]?.doctor_user_id ?? v.doctor_user_id ?? '',
                        },
                      }))}
                    >
                      <option value="">Department</option>
                      {departments.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
                    </select>
                    <select
                      value={assignments[v.id]?.doctor_user_id ?? v.doctor_user_id ?? ''}
                      onChange={(e) => setAssignments((all) => ({
                        ...all,
                        [v.id]: {
                          department_id: assignments[v.id]?.department_id ?? v.department_id ?? '',
                          doctor_user_id: e.target.value,
                        },
                      }))}
                    >
                      <option value="">Doctor</option>
                      {doctors
                        .filter((d) => d.department_id === (assignments[v.id]?.department_id ?? v.department_id))
                        .map((d) => <option key={d.user_id} value={d.user_id}>{d.full_name}</option>)}
                    </select>
                    <button className="secondary" disabled={saving === v.id} onClick={() => saveAssignment(v)}>
                      {saving === v.id ? 'Saving…' : 'Save'}
                    </button>
                  </td>
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
