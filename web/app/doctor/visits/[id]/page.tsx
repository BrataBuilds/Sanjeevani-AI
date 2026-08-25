'use client';

import { useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import { useParams, useRouter } from 'next/navigation';
import { api, fmtTime } from '../../../../lib/api';
import { RequireRole } from '../../../../lib/session';
import { AuthFile, Status, Urgency } from '../../../ui';

type Detail = {
  visit: any;
  patient: any;
  conditions: { kind: string; label: string; notes: string | null }[];
  relatives: { name: string; contact: string; relation: string; notify: boolean }[];
  documents: { id: string; label: string; description: string | null; mime: string; file_id: string; url: string; created_at: string }[];
  triage: any | null;
  ai_conversation_id: string | null;
};

export default function VisitPage() {
  return (
    <RequireRole role="doctor">
      <VisitDetail />
    </RequireRole>
  );
}

function VisitDetail() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const [d, setD] = useState<Detail | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [notes, setNotes] = useState('');
  const [urgency, setUrgency] = useState('');

  const load = useCallback(async () => {
    try {
      const out = await api<Detail>(`/doctor/visits/${id}`);
      setD(out);
      setNotes(out.visit.doctor_notes ?? '');
      setUrgency(String(out.visit.urgency));
    } catch (err: any) {
      setError(err?.message ?? 'could not load visit');
    }
  }, [id]);

  useEffect(() => {
    load();
  }, [load]);

  async function patch(body: Record<string, unknown>) {
    setBusy(true);
    setError(null);
    try {
      await api(`/doctor/visits/${id}`, { method: 'PATCH', body });
      await load();
    } catch (err: any) {
      setError(err?.message ?? 'update failed');
    } finally {
      setBusy(false);
    }
  }

  async function openCareTeamChat() {
    if (!d) return;
    const conv = await api<{ id: string }>(`/doctor/patients/${d.visit.patient_id}/conversation`, {
      method: 'POST',
    });
    router.push(`/doctor/conversations/${conv.id}`);
  }

  if (error && !d) return <p className="error">{error}</p>;
  if (!d) return <p className="muted">Loading…</p>;

  const t = d.triage;
  const isPlaceholder =
    t && (t.confidence === 0 || JSON.stringify(t.sources ?? '').includes('stub://'));

  return (
    <>
      <p className="small">
        <Link href="/doctor">← Queue</Link>
      </p>
      <h1>
        Token #{d.visit.token_no} · {d.patient.full_name}
      </h1>
      <p className="muted small">
        {d.visit.hospital_name} · {d.visit.department_name ?? 'no department'} ·{' '}
        {fmtTime(d.visit.created_at)}
      </p>

      {t?.red_flag && (
        <div className="redflag">
          Emergency red flag raised at intake. Assess immediately.
        </div>
      )}
      {isPlaceholder && (
        <p className="notice">
          This report came from the placeholder triage stub — no triage service is connected yet,
          so the specialty and urgency below are sample values.
        </p>
      )}
      {error && <p className="error">{error}</p>}

      <div className="cols2">
        <div>
          <div className="panel">
            <h2 style={{ marginTop: 0 }}>Preliminary report</h2>
            {!t && <p className="muted">No triage report — this visit was registered manually.</p>}
            {t && (
              <>
                <dl className="kv">
                  <dt>Chief complaint</dt>
                  <dd>{t.chief_complaint ?? '—'}</dd>
                  <dt>Suggested specialty</dt>
                  <dd>{t.specialty ?? '—'}</dd>
                  <dt>Urgency (as triaged)</dt>
                  <dd>
                    <Urgency value={t.urgency} />
                  </dd>
                  <dt>Confidence</dt>
                  <dd>{t.confidence === null ? '—' : `${Math.round(t.confidence * 100)}%`}</dd>
                </dl>

                {Array.isArray(t.symptoms) && t.symptoms.length > 0 && (
                  <>
                    <h2>Symptoms</h2>
                    <ul className="plain small">
                      {t.symptoms.map((s: any, i: number) => (
                        <li key={i}>
                          {s.name}
                          {s.duration ? ` · ${s.duration}` : ''}
                          {s.severity ? ` · ${s.severity}` : ''}
                        </li>
                      ))}
                    </ul>
                  </>
                )}

                {t.clinical_note && (
                  <>
                    <h2>Clinical note</h2>
                    <p className="small">{t.clinical_note}</p>
                  </>
                )}
                {t.summary && (
                  <>
                    <h2>Shown to the patient</h2>
                    <p className="small muted">{t.summary}</p>
                  </>
                )}
                {Array.isArray(t.sources) && t.sources.length > 0 && (
                  <>
                    <h2>Sources</h2>
                    <ul className="plain small">
                      {t.sources.map((s: any, i: number) => (
                        <li key={i}>
                          {s.title ?? 'source'} <span className="muted">{s.ref ?? ''}</span>
                        </li>
                      ))}
                    </ul>
                  </>
                )}
              </>
            )}
          </div>

          <div className="panel">
            <h2 style={{ marginTop: 0 }}>Medical history</h2>
            {d.documents.length === 0 && <p className="muted small">No documents uploaded.</p>}
            <div className="row">
              {d.documents.map((doc) => (
                <div key={doc.id} style={{ maxWidth: 180 }}>
                  <AuthFile path={doc.url} mime={doc.mime} label={doc.label} />
                  <div className="small">
                    <strong>{doc.label}</strong>
                    <div className="muted">{doc.description}</div>
                    <div className="muted">{fmtTime(doc.created_at)}</div>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>

        <div>
          <div className="panel">
            <h2 style={{ marginTop: 0 }}>Your decision</h2>
            <p className="small muted">
              The triage suggestion is never final. Every change here is written to the audit log.
            </p>

            <label htmlFor="urg">Urgency</label>
            <select id="urg" value={urgency} onChange={(e) => setUrgency(e.target.value)}>
              {[1, 2, 3, 4, 5].map((n) => (
                <option key={n} value={n}>
                  {n}
                </option>
              ))}
            </select>
            <button
              style={{ marginTop: 8 }}
              disabled={busy || Number(urgency) === d.visit.urgency}
              onClick={() => patch({ urgency: Number(urgency) })}
            >
              Save urgency
            </button>

            <label htmlFor="notes" style={{ marginTop: 14 }}>
              Notes
            </label>
            <textarea id="notes" value={notes} onChange={(e) => setNotes(e.target.value)} />
            <button className="secondary" disabled={busy} onClick={() => patch({ doctor_notes: notes })}>
              Save notes
            </button>

            <h2>Queue status</h2>
            <p>
              <Status value={d.visit.status} />
              {d.visit.urgency_overridden && <span className="small muted"> · urgency overridden</span>}
            </p>
            <div className="row">
              {!d.visit.doctor_user_id && (
                <button disabled={busy} onClick={() => patch({ claim: true })}>
                  Claim
                </button>
              )}
              {d.visit.status === 'waiting' && (
                <button disabled={busy} onClick={() => patch({ status: 'in_consult', claim: true })}>
                  Start consult
                </button>
              )}
              {d.visit.status === 'in_consult' && (
                <button disabled={busy} onClick={() => patch({ status: 'done' })}>
                  Mark done
                </button>
              )}
              <button className="secondary" disabled={busy} onClick={() => patch({ status: 'referred' })}>
                Refer out
              </button>
            </div>
          </div>

          <div className="panel">
            <h2 style={{ marginTop: 0 }}>Patient</h2>
            <dl className="kv">
              <dt>Age / gender</dt>
              <dd>{[d.patient.age ? `${d.patient.age}y` : null, d.patient.gender].filter(Boolean).join(' · ') || '—'}</dd>
              <dt>Blood type</dt>
              <dd>{d.patient.blood_type ?? '—'}</dd>
              <dt>Phone</dt>
              <dd>{d.patient.phone ?? '—'}</dd>
              <dt>Email</dt>
              <dd className="small">{d.patient.email}</dd>
              <dt>Address</dt>
              <dd className="small">{d.patient.address ?? '—'}</dd>
              <dt>Insurance</dt>
              <dd className="small">
                {d.patient.insurance_provider
                  ? `${d.patient.insurance_provider} · ${d.patient.policy_number ?? 'no policy no.'}`
                  : '—'}
              </dd>
              <dt>Aadhaar</dt>
              <dd className="small">
                {d.patient.aadhaar_verified ? `•••• ${d.patient.aadhaar_last4}` : 'not linked'}
              </dd>
            </dl>

            <h2>Known conditions</h2>
            {d.conditions.length === 0 && <p className="muted small">None recorded.</p>}
            <ul className="plain small">
              {d.conditions.map((c, i) => (
                <li key={i}>
                  <strong>{c.kind}</strong>: {c.label}
                  {c.notes ? ` — ${c.notes}` : ''}
                </li>
              ))}
            </ul>

            <h2>Emergency contacts</h2>
            {d.relatives.length === 0 && <p className="muted small">None on file.</p>}
            <ul className="plain small">
              {d.relatives.map((r, i) => (
                <li key={i}>
                  {r.name} ({r.relation}) — {r.contact}
                  {r.notify ? '' : ' · do not notify'}
                </li>
              ))}
            </ul>
          </div>

          <div className="panel">
            <h2 style={{ marginTop: 0 }}>Conversations</h2>
            <div className="row">
              {d.ai_conversation_id && (
                <Link href={`/doctor/conversations/${d.ai_conversation_id}`}>
                  Read intake transcript
                </Link>
              )}
              <button className="secondary" onClick={openCareTeamChat}>
                Message patient
              </button>
            </div>
          </div>
        </div>
      </div>
    </>
  );
}
