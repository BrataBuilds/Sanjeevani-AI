'use client';

import { useCallback, useEffect, useState } from 'react';
import { api } from '../../../lib/api';
import { RequireRole } from '../../../lib/session';

type Doctor = {
  user_id: string;
  full_name: string;
  email: string;
  is_active: boolean;
  is_available: boolean;
  specialty: string | null;
  reg_no: string | null;
  department_id: string | null;
  department_name: string | null;
  queue_today: number;
};

type Department = { id: string; name: string; specialty: string; doctors: number; waiting: number };

export default function DoctorsPage() {
  return (
    <RequireRole role="admin">
      <Staff />
    </RequireRole>
  );
}

function Staff() {
  const [doctors, setDoctors] = useState<Doctor[]>([]);
  const [departments, setDepartments] = useState<Department[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    try {
      const [d, dep] = await Promise.all([
        api<Doctor[]>('/admin/doctors'),
        api<Department[]>('/admin/departments'),
      ]);
      setDoctors(d);
      setDepartments(dep);
    } catch (err: any) {
      setError(err?.message ?? 'could not load staff');
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  async function act(fn: () => Promise<unknown>) {
    setBusy(true);
    setError(null);
    try {
      await fn();
      await load();
    } catch (err: any) {
      setError(err?.message ?? 'request failed');
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <h1>Staff &amp; departments</h1>
      <p className="muted small">
        Doctors never sign up themselves — accounts are created here and the password is handed over
        out of band.
      </p>
      {error && <p className="error">{error}</p>}

      <h2>Doctors</h2>
      <div className="table-scroll">
        <table>
          <thead>
            <tr>
              <th>Name</th>
              <th>Email</th>
              <th>Department</th>
              <th>Reg. no</th>
              <th>Queue today</th>
              <th>Available</th>
              <th>Account</th>
            </tr>
          </thead>
          <tbody>
            {doctors.map((d) => (
              <tr key={d.user_id}>
                <td>{d.full_name}</td>
                <td className="small">{d.email}</td>
                <td>
                  <select
                    value={d.department_id ?? ''}
                    disabled={busy}
                    onChange={(e) =>
                      act(() =>
                        api(`/admin/doctors/${d.user_id}`, {
                          method: 'PATCH',
                          body: { department_id: e.target.value || null },
                        }),
                      )
                    }
                  >
                    <option value="">Unassigned</option>
                    {departments.map((dep) => (
                      <option key={dep.id} value={dep.id}>
                        {dep.name}
                      </option>
                    ))}
                  </select>
                </td>
                <td className="small">{d.reg_no ?? '—'}</td>
                <td>{d.queue_today}</td>
                <td>
                  <span className="switch">
                    <button
                      type="button"
                      className={`switch-btn${d.is_available ? ' on' : ''}`}
                      disabled={busy}
                      aria-label={d.is_available ? 'On duty' : 'Off duty'}
                      onClick={() =>
                        act(() =>
                          api(`/admin/doctors/${d.user_id}`, {
                            method: 'PATCH',
                            body: { is_available: !d.is_available },
                          }),
                        )
                      }
                    >
                      <span className="knob" />
                    </button>
                    <span className="small" style={{ color: d.is_available ? 'var(--acc)' : 'var(--ink2)' }}>
                      {d.is_available ? 'On duty' : 'Off duty'}
                    </span>
                  </span>
                </td>
                <td>
                  <button
                    className="secondary"
                    disabled={busy}
                    style={!d.is_active ? { borderColor: 'var(--dan)', color: 'var(--dan)' } : undefined}
                    onClick={() =>
                      act(() =>
                        api(`/admin/doctors/${d.user_id}`, {
                          method: 'PATCH',
                          body: { is_active: !d.is_active },
                        }),
                      )
                    }
                  >
                    {d.is_active ? 'Active' : 'Disabled'}
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <NewDoctor departments={departments} onDone={load} />

      <h2>Departments</h2>
      <div className="table-scroll">
        <table>
          <thead>
            <tr>
              <th>Name</th>
              <th>Specialty key</th>
              <th>Doctors</th>
              <th>Waiting today</th>
            </tr>
          </thead>
          <tbody>
            {departments.map((d) => (
              <tr key={d.id}>
                <td>{d.name}</td>
                <td>
                  <code className="small">{d.specialty}</code>
                </td>
                <td>{d.doctors}</td>
                <td>{d.waiting}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <NewDepartment onDone={load} />
    </>
  );
}

function NewDoctor({ departments, onDone }: { departments: Department[]; onDone: () => void }) {
  const [form, setForm] = useState({ full_name: '', email: '', password: '', department_id: '', reg_no: '' });
  const [msg, setMsg] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const set = (k: string) => (e: any) => setForm({ ...form, [k]: e.target.value });

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    setMsg(null);
    try {
      await api('/admin/doctors', {
        method: 'POST',
        body: { ...form, department_id: form.department_id || undefined, reg_no: form.reg_no || undefined },
      });
      setMsg(`Created ${form.email}. Give them the password directly — it is not emailed.`);
      setForm({ full_name: '', email: '', password: '', department_id: '', reg_no: '' });
      onDone();
    } catch (err: any) {
      setError(err?.message ?? 'could not create doctor');
    } finally {
      setBusy(false);
    }
  }

  return (
    <form className="panel" onSubmit={submit}>
      <h2 style={{ marginTop: 0 }}>Add a doctor</h2>
      <div className="row">
        <div>
          <label htmlFor="dn">Full name</label>
          <input id="dn" value={form.full_name} onChange={set('full_name')} required />
        </div>
        <div>
          <label htmlFor="de">Email</label>
          <input id="de" type="email" value={form.email} onChange={set('email')} required />
        </div>
        <div>
          <label htmlFor="dp">Temporary password</label>
          <input id="dp" type="password" minLength={8} value={form.password} onChange={set('password')} required />
        </div>
        <div>
          <label htmlFor="dd">Department</label>
          <select id="dd" value={form.department_id} onChange={set('department_id')}>
            <option value="">Unassigned</option>
            {departments.map((d) => (
              <option key={d.id} value={d.id}>
                {d.name}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label htmlFor="dr">Reg. no</label>
          <input id="dr" value={form.reg_no} onChange={set('reg_no')} />
        </div>
        <button type="submit" disabled={busy}>
          Create
        </button>
      </div>
      {msg && <p className="small">{msg}</p>}
      {error && <p className="error small">{error}</p>}
    </form>
  );
}

function NewDepartment({ onDone }: { onDone: () => void }) {
  const [name, setName] = useState('');
  const [specialty, setSpecialty] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await api('/admin/departments', { method: 'POST', body: { name, specialty } });
      setName('');
      setSpecialty('');
      onDone();
    } catch (err: any) {
      setError(err?.message ?? 'could not create department');
    } finally {
      setBusy(false);
    }
  }

  return (
    <form className="panel" onSubmit={submit}>
      <h2 style={{ marginTop: 0 }}>Add a department</h2>
      <p className="muted small">
        The specialty key is what the triage layer returns when it routes a patient here. It gets
        slugified, so “ENT / Otolaryngology” becomes <code>ent_otolaryngology</code>.
      </p>
      <div className="row">
        <div>
          <label htmlFor="pn">Display name</label>
          <input id="pn" value={name} onChange={(e) => setName(e.target.value)} required />
        </div>
        <div>
          <label htmlFor="ps">Specialty key</label>
          <input id="ps" value={specialty} onChange={(e) => setSpecialty(e.target.value)} required />
        </div>
        <button type="submit" disabled={busy}>
          Create
        </button>
      </div>
      {error && <p className="error small">{error}</p>}
    </form>
  );
}
