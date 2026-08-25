'use client';

import { useEffect, useState } from 'react';
import { URGENCY_LABEL, fetchBlobUrl } from '../lib/api';

export function Urgency({ value, overridden }: { value?: number | null; overridden?: boolean }) {
  if (!value) return <span className="tag">—</span>;
  return (
    <span className={`tag u${value}`} title={overridden ? 'overridden by a doctor' : 'as triaged'}>
      {URGENCY_LABEL[value] ?? value}
      {overridden ? ' ✎' : ''}
    </span>
  );
}

export function Status({ value }: { value: string }) {
  return <span className="tag">{value.replace('_', ' ')}</span>;
}

export function Stat({ n, k }: { n: number | string | null | undefined; k: string }) {
  return (
    <div className="stat">
      <div className="n">{n ?? '—'}</div>
      <div className="k">{k}</div>
    </div>
  );
}

/** Bar chart without a chart library — a div is wide enough. */
export function Bars({ rows }: { rows: { label: string; value: number; sub?: string }[] }) {
  const max = Math.max(1, ...rows.map((r) => r.value));
  if (!rows.length) return <p className="muted small">No data yet.</p>;
  return (
    <div>
      {rows.map((r) => (
        <div key={r.label} style={{ marginBottom: 6 }}>
          <div className="small" style={{ display: 'flex', justifyContent: 'space-between' }}>
            <span>{r.label}</span>
            <span className="muted">{r.sub ?? r.value}</span>
          </div>
          <div style={{ background: '#e6e9ee', borderRadius: 3, height: 8 }}>
            <div
              style={{
                width: `${(r.value / max) * 100}%`,
                background: 'var(--accent)',
                height: '100%',
                borderRadius: 3,
              }}
            />
          </div>
        </div>
      ))}
    </div>
  );
}

/** Files need the auth header, so they arrive as a blob rather than a plain src. */
export function AuthFile({ path, mime, label }: { path: string; mime: string; label: string }) {
  const [url, setUrl] = useState<string | null>(null);
  const [error, setError] = useState(false);

  useEffect(() => {
    let live = true;
    let objectUrl: string | null = null;
    fetchBlobUrl(path)
      .then((u) => {
        objectUrl = u;
        if (live) setUrl(u);
        else URL.revokeObjectURL(u);
      })
      .catch(() => live && setError(true));
    return () => {
      live = false;
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    };
  }, [path]);

  if (error) return <span className="small error">could not load {label}</span>;
  if (!url) return <span className="small muted">loading {label}…</span>;
  if (mime.startsWith('image/')) {
    return (
      <a href={url} target="_blank" rel="noreferrer">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={url} alt={label} style={{ maxWidth: 160, border: '1px solid var(--line)', borderRadius: 4 }} />
      </a>
    );
  }
  return (
    <a href={url} target="_blank" rel="noreferrer">
      Open {label}
    </a>
  );
}
