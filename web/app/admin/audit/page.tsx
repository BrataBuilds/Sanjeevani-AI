'use client';

import { useCallback } from 'react';
import { api, fmtTime } from '../../../lib/api';
import { RequireRole, usePolling } from '../../../lib/session';

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

function Audit() {
  const load = useCallback(() => api<Entry[]>('/admin/audit?limit=200'), []);
  const { data, error, pending, refresh } = usePolling(load, 30000);

  return (
    <>
      <h1>Audit trail</h1>
      <p className="muted small">
        Triage results, urgency overrides, staff changes. Newest first, last 200 entries.
      </p>
      <div className="panel row">
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
                <th>When</th>
                <th>Action</th>
                <th>Actor</th>
                <th>Entity</th>
                <th>Detail</th>
              </tr>
            </thead>
            <tbody>
              {data.map((e) => (
                <tr key={e.id}>
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
