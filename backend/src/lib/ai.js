/**
 * The AI / RAG seam. THIS FILE IS THE BOUNDARY, NOT THE IMPLEMENTATION.
 *
 * Another team owns triage: entity extraction, the red-flag rule engine, the
 * vector search, and report synthesis (Design_doc.md §5). Nothing in this repo
 * decides a specialty, an urgency score, or whether something is an emergency.
 *
 * Two ways for that team to plug in — both speak the same JSON contract, which
 * is documented in docs/AI-Integration-Contract.md:
 *
 *   1. Synchronous  — set AI_SERVICE_URL. We POST {AI_SERVICE_URL}/triage and
 *                     use the response body directly.
 *   2. Asynchronous — the same POST may answer 202 with no result; the service
 *                     later calls POST /ai/triage-callback with `request_id`.
 *
 * With AI_SERVICE_URL unset, stubTriage() returns obviously-canned placeholder
 * data so the app and dashboards are fully demoable with no AI service running.
 */

const URL_BASE = (process.env.AI_SERVICE_URL || '').replace(/\/$/, '');
const TOKEN = process.env.AI_SERVICE_TOKEN || '';
const TIMEOUT_MS = Number(process.env.AI_TIMEOUT_MS || 20000);

export const aiConfigured = () => Boolean(URL_BASE);

/**
 * @returns {Promise<{source:'stub'|'http', pending:boolean, result:object|null}>}
 *   pending=true means "accepted, answer will arrive on the callback".
 */
export async function requestTriage(payload) {
  if (!URL_BASE) return { source: 'stub', pending: false, result: stubTriage(payload) };

  const res = await fetch(`${URL_BASE}/triage`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      ...(TOKEN ? { authorization: `Bearer ${TOKEN}` } : {}),
    },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });

  if (res.status === 202) return { source: 'http', pending: true, result: null };
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`ai service ${res.status}: ${text.slice(0, 300)}`);
  }
  return { source: 'http', pending: false, result: await res.json() };
}

/**
 * Shape-check whatever the AI side sent us before it touches the database.
 * Deliberately permissive on the optional fields — we clamp, we do not reject a
 * whole triage because a nice-to-have field is the wrong type.
 */
export function normaliseTriage(raw) {
  const r = raw && typeof raw === 'object' ? raw : {};
  const arr = (v) => (Array.isArray(v) ? v : null);
  const clampUrgency = (v) => {
    const n = Number(v);
    if (!Number.isFinite(n)) return null;
    return Math.min(5, Math.max(1, Math.round(n)));
  };
  return {
    reply: typeof r.reply === 'string' ? r.reply : null,
    status: ['ok', 'needs_more_info', 'emergency'].includes(r.status) ? r.status : 'ok',
    chief_complaint: typeof r.chief_complaint === 'string' ? r.chief_complaint : null,
    symptoms: arr(r.symptoms),
    specialty: typeof r.specialty === 'string' ? r.specialty : null,
    urgency: clampUrgency(r.urgency),
    red_flag: r.red_flag === true,
    summary: typeof r.summary === 'string' ? r.summary : null,
    clinical_note: typeof r.clinical_note === 'string' ? r.clinical_note : null,
    confidence: Number.isFinite(Number(r.confidence)) ? Number(r.confidence) : null,
    sources: arr(r.sources),
    follow_up_questions: arr(r.follow_up_questions),
    suggested_hospitals: arr(r.suggested_hospitals),
    raw: r,
  };
}

// ---------------------------------------------------------------------------
// Placeholder only. Returns fixed text plus whatever hospitals the caller
// already looked up. It reads the message count purely to alternate between the
// "asks follow-up MCQs" and "returns a report" screens so both UIs can be
// demoed. There is no clinical logic here and none should be added.
// ---------------------------------------------------------------------------
function stubTriage(payload) {
  const turns = (payload?.conversation?.messages || []).filter((m) => m.role === 'patient').length;
  const complaint = [...(payload?.conversation?.messages || [])]
    .reverse()
    .find((m) => m.role === 'patient' && m.body)?.body;

  if (turns < 2) {
    return {
      request_id: payload?.request_id,
      status: 'needs_more_info',
      reply:
        'Thanks, noted. (Placeholder response — no triage model is connected yet.) ' +
        'A couple of quick questions so the right department can be suggested.',
      chief_complaint: complaint || null,
      follow_up_questions: [
        {
          id: 'duration',
          question: 'How long have you had this problem?',
          options: ['Less than a day', '1-3 days', 'About a week', 'Longer than a week'],
          multi: false,
        },
        {
          id: 'severity',
          question: 'How would you describe it right now?',
          options: ['Mild', 'Uncomfortable', 'Severe'],
          multi: false,
        },
      ],
      sources: [{ title: 'placeholder', ref: 'stub://no-model-connected' }],
    };
  }

  return {
    request_id: payload?.request_id,
    status: 'ok',
    reply:
      'Here is a preliminary summary. (Placeholder response — no triage model is ' +
      'connected yet, so the department and urgency below are sample values.)',
    chief_complaint: complaint || 'Not captured',
    symptoms: [{ name: 'as described by patient', duration: 'unknown', severity: 'unknown' }],
    specialty: 'general_medicine',
    urgency: 3,
    red_flag: false,
    confidence: 0,
    summary:
      'Sample summary. Once the triage service is connected, this paragraph is the ' +
      'plain-language explanation shown to the patient.',
    clinical_note: 'SAMPLE. Awaiting triage service. No clinical content generated by this server.',
    sources: [{ title: 'placeholder', ref: 'stub://no-model-connected' }],
    suggested_hospitals: (payload?.hospitals || []).slice(0, 3).map((h) => ({
      hospital_id: h.id,
      name: h.name,
      distance_km: h.distance_km ?? null,
      reason: 'Sample suggestion (nearest facilities on record).',
    })),
  };
}
