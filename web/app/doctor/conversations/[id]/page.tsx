'use client';

import { useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import { useParams } from 'next/navigation';
import { api, fmtTime } from '../../../../lib/api';
import { RequireRole } from '../../../../lib/session';
import { AuthFile, Urgency } from '../../../ui';

type Msg = {
  id: string;
  sender_role: 'patient' | 'ai' | 'doctor' | 'system';
  sender_name: string | null;
  kind: string;
  body: string | null;
  payload: any;
  file_id: string | null;
  file_url?: string;
  created_at: string;
};

/**
 * One page for both thread kinds. A care_team thread is writable; an 'ai' intake
 * transcript is read-only for staff (can_post comes back false), which keeps the
 * patient's assistant thread honest.
 */
export default function ConversationPage() {
  return (
    <RequireRole role="doctor">
      <Thread />
    </RequireRole>
  );
}

function Thread() {
  const { id } = useParams<{ id: string }>();
  const [meta, setMeta] = useState<any>(null);
  const [messages, setMessages] = useState<Msg[]>([]);
  const [draft, setDraft] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    try {
      const [m, msgs] = await Promise.all([
        api<any>(`/conversations/${id}`),
        api<{ messages: Msg[] }>(`/conversations/${id}/messages`),
      ]);
      setMeta(m);
      setMessages(msgs.messages);
    } catch (err: any) {
      setError(err?.message ?? 'could not load conversation');
    }
  }, [id]);

  useEffect(() => {
    load();
    const t = setInterval(load, 8000);
    return () => clearInterval(t);
  }, [load]);

  async function send(e: React.FormEvent) {
    e.preventDefault();
    if (!draft.trim()) return;
    setBusy(true);
    try {
      await api(`/conversations/${id}/messages`, { method: 'POST', body: { body: draft } });
      setDraft('');
      await load();
    } catch (err: any) {
      setError(err?.message ?? 'send failed');
    } finally {
      setBusy(false);
    }
  }

  if (error && !meta) return <p className="error">{error}</p>;
  if (!meta) return <p className="muted">Loading…</p>;

  return (
    <>
      <p className="small">
        <Link href={meta.kind === 'ai' ? '/doctor' : '/doctor/messages'}>← Back</Link>
      </p>
      <h1>
        {meta.kind === 'ai' ? 'Intake transcript' : 'Care team chat'} · {meta.patient?.full_name}
      </h1>
      <p className="muted small">
        {meta.kind === 'ai'
          ? 'Read-only. This is what the patient told the triage assistant.'
          : 'The patient sees these messages in the app.'}
      </p>

      <div className="panel">
        {messages.length === 0 && <p className="muted small">No messages yet.</p>}
        {messages.map((m) => (
          <Bubble key={m.id} m={m} />
        ))}
      </div>

      {meta.can_post ? (
        <form onSubmit={send} className="panel">
          <label htmlFor="draft">Reply</label>
          <textarea
            id="draft"
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            placeholder="Type a message to the patient"
          />
          {error && <p className="error small">{error}</p>}
          <button type="submit" disabled={busy || !draft.trim()}>
            {busy ? 'Sending…' : 'Send'}
          </button>
        </form>
      ) : (
        <p className="muted small">You cannot post in this thread.</p>
      )}
    </>
  );
}

const WHO: Record<string, string> = {
  patient: 'Patient',
  ai: 'Assistant',
  doctor: 'Care team',
  system: 'System',
};

const BUBBLE_CLASS: Record<string, string> = {
  patient: 'bubble-patient',
  ai: 'bubble-ai',
  doctor: 'bubble-doctor',
  system: 'bubble-system',
};

function Bubble({ m }: { m: Msg }) {
  return (
    <div className={`bubble ${BUBBLE_CLASS[m.sender_role] ?? 'bubble-patient'}`}>
      {m.body && <div className="bubble-body">{m.body}</div>}

      {m.kind === 'mcq' && Array.isArray(m.payload?.questions) && (
        <div className="bubble-body" style={{ maxWidth: '100%' }}>
          <ul className="plain small" style={{ margin: 0 }}>
            {m.payload.questions.map((q: any) => (
              <li key={q.id}>
                {q.question} <span className="muted">[{(q.options ?? []).join(' / ')}]</span>
              </li>
            ))}
          </ul>
        </div>
      )}

      {m.kind === 'report' && m.payload && (
        <div className="bubble-body" style={{ maxWidth: '100%' }}>
          <Urgency value={m.payload.urgency} />{' '}
          {m.payload.specialty && <span className="tag">{m.payload.specialty}</span>}
          {m.payload.red_flag && <span className="tag u1"> red flag</span>}
        </div>
      )}

      {m.kind === 'hospital_suggestion' && Array.isArray(m.payload?.hospitals) && (
        <div className="bubble-body" style={{ maxWidth: '100%' }}>
          <ul className="plain small" style={{ margin: 0 }}>
            {m.payload.hospitals.map((h: any, i: number) => (
              <li key={i}>
                {h.name}
                {h.distance_km != null ? ` · ${h.distance_km} km` : ''} — {h.reason}
              </li>
            ))}
          </ul>
        </div>
      )}

      {m.file_url && <AuthFile path={m.file_url} mime={m.kind === 'audio' ? 'audio/*' : 'image/*'} label="attachment" />}

      <div className="bubble-meta">
        {WHO[m.sender_role] ?? m.sender_role}
        {m.sender_name ? ` · ${m.sender_name}` : ''} · {fmtTime(m.created_at)}
        {m.kind !== 'text' && <span className="tag">{m.kind}</span>}
      </div>
    </div>
  );
}
