'use client';

import { useEffect, useState } from 'react';
import { URGENCY_LABEL, fetchBlobUrl } from '../lib/api';

/** Numeral, notch height and word all carry the level — colour is a fourth
 * channel, never the only one. Same language as the patient app's urgency
 * scale and the canvas's `urgency()` helper: 1–2 danger, 3 mid, 4–5 neutral. */
function urgencyColor(level: number) {
  return level <= 2 ? 'var(--dan)' : level === 3 ? 'var(--mid)' : 'var(--ink2)';
}

export function Urgency({ value, overridden }: { value?: number | null; overridden?: boolean }) {
  if (!value) return <span className="tag">—</span>;
  const fg = urgencyColor(value);
  const filled = 6 - value;
  return (
    <span
      className={`tag u${value}`}
      title={overridden ? 'overridden by a doctor' : 'as triaged'}
      style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}
    >
      <span style={{ fontFamily: 'var(--serif)', fontSize: 15, lineHeight: 1, color: fg }}>{value}</span>
      <span style={{ display: 'inline-flex', gap: 2, alignItems: 'flex-end' }}>
        {[1, 2, 3, 4, 5].map((i) => (
          <span
            key={i}
            style={{
              width: 3,
              height: 4 + i * 2,
              borderRadius: 1,
              background: i <= filled ? fg : 'transparent',
              border: `1px solid ${i <= filled ? fg : 'var(--line)'}`,
            }}
          />
        ))}
      </span>
      {URGENCY_LABEL[value] ?? value}
      {overridden ? ' ✎' : ''}
    </span>
  );
}

const STATUS_LABEL: Record<string, string> = {
  in_consult: 'in consult',
  waiting: 'waiting',
  claimed: 'claimed',
  done: 'done',
  referred: 'referred',
  cancelled: 'cancelled',
};

export function Status({ value }: { value: string }) {
  return <span className={`tag st-${value}`}>{STATUS_LABEL[value] ?? value.replace('_', ' ')}</span>;
}

export function Stat({
  n,
  k,
  tone,
}: {
  n: number | string | null | undefined;
  k: string;
  tone?: 'danger' | 'warn';
}) {
  return (
    <div className={`stat${tone ? ` tone-${tone}` : ''}`}>
      <div className="k">{k}</div>
      <div className="n">{n ?? '—'}</div>
    </div>
  );
}

/** Bar chart without a chart library — a labelled row with a filled track,
 * same shape as the canvas's dashboard rows. */
export function Bars({ rows }: { rows: { label: string; value: number; sub?: string }[] }) {
  const max = Math.max(1, ...rows.map((r) => r.value));
  if (!rows.length) return <p className="muted small">No data yet.</p>;
  return (
    <div>
      {rows.map((r) => (
        <div className="bars-row" key={r.label}>
          <div className="label-line">
            <span>{r.label}</span>
            <span>{r.sub ?? r.value}</span>
          </div>
          <div className="bars-track">
            <div style={{ width: `${(r.value / max) * 100}%` }} />
          </div>
        </div>
      ))}
    </div>
  );
}

/** Segmented filter control — the canvas's recurring scope/status/window picker. */
export function Pills<T extends string>({
  value,
  onChange,
  options,
}: {
  value: T;
  onChange: (v: T) => void;
  options: { value: T; label: string }[];
}) {
  return (
    <div className="pillbar">
      {options.map((o) => (
        <button
          key={o.value}
          type="button"
          className={o.value === value ? 'active' : undefined}
          onClick={() => onChange(o.value)}
        >
          {o.label}
        </button>
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
