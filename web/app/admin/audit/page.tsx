'use client';

import { useCallback, useState } from 'react';
import { api, fmtTime } from '../../../lib/api';
import { RequireRole, usePolling } from '../../../lib/session';
import { Pills } from '../../ui';

type Entry = {
  id: number;
  action: string;
  entity: string | null;
  entity_id: string | null;
  detail: any;
  created_at: string;
  actor_name: string | null;
  actor_role: string | null;
};

/**
 * Design_doc.md §6 wants every triage recommendation and every doctor override
 * recoverable after the fact. This is that trail, unfiltered.
 */
export default function AuditPage() {
  return (
    <RequireRole role="admin">
      <Audit />
    </RequireRole>
  );
}

type Filter = 'all' | 'triage' | 'override' | 'queue' | 'staff';

/** The five action strings that ever reach a hospital's trail (see backend
 * audit() call sites): admin.* for staff/department changes, triage.result_applied
 * for AI suggestions, and visit.updated for everything a doctor does to a visit —
 * split into "override" vs "queue" by whether detail.urgency_to is set, which is
 * the only field that says a doctor actually changed the urgency. */
function bucket(e: Entry): Exclude<Filter, 'all'> {
  if (e.action.startsWith('admin.')) return 'staff';
  if (e.action === 'triage.result_applied') return 'triage';
  if (e.detail?.urgency_to !== undefined) return 'override';
  return 'queue';
}

function Audit() {
  const load = useCallback(() => api<Entry[]>('/admin/audit?limit=200'), []);
  const { data, error, pending, refresh } = usePolling(load, 30000);
  const [filter, setFilter] = useState<Filter>('all');
  const rows = data?.filter((e) => filter === 'all' || bucket(e) === filter);

  return (
    <>
      <h1>Audit trail</h1>
      <p className="muted small">
        Triage results, urgency overrides, staff changes. Newest first, last 200 entries.
      </p>
      <div className="row" style={{ marginBottom: 14, alignItems: 'center' }}>
        <Pills
          value={filter}
          onChange={setFilter}
          options={[
            { value: 'all', label: 'All' },
            { value: 'triage', label: 'Triage' },
            { value: 'override', label: 'Overrides' },
            { value: 'queue', label: 'Queue' },
            { value: 'staff', label: 'Staff' },
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
                <th>When</th>
                <th>Action</th>
                <th>Actor</th>
                <th>Entity</th>
                <th>Detail</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((e) => (
                <tr key={e.id} className={bucket(e) === 'override' ? 'row-diverged' : undefined}>
                  <td className="small">{fmtTime(e.created_at)}</td>
                  <td className="small">
                    <code>{e.action}</code>
                  </td>
                  <td className="small">
                    {e.actor_name ?? <span className="muted">system</span>}
                    {e.actor_role ? ` · ${e.actor_role}` : ''}
                  </td>
                  <td className="small">
                    {e.entity ?? '—'}
                    {e.entity_id && <div className="muted">{e.entity_id.slice(0, 8)}…</div>}
                  </td>
                  <td>
                    {bucket(e) === 'override' && (
                      <div className="tag" style={{ background: 'var(--midSoft)', color: 'var(--mid)', marginBottom: 6 }}>
                        disagreement · AI {e.detail.ai_urgency ?? e.detail.urgency_from} → doctor {e.detail.urgency_to}
                      </div>
                    )}
                    {e.detail ? (
                      <pre className="json">{JSON.stringify(e.detail)}</pre>
                    ) : (
                      <span className="muted small">—</span>
                    )}
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
