/**
 * The AI / RAG boundary. The platform sends exactly one patient message to the
 * RAG service's /chat endpoint and translates its small response into the
 * existing persistence shape. It deliberately does not reconstruct a second
 * triage protocol from the transcript.
 */

const URL_BASE = (process.env.AI_SERVICE_URL || '').replace(/\/$/, '');
const TOKEN = process.env.AI_SERVICE_TOKEN || '';
const TIMEOUT_MS = Number(process.env.AI_TIMEOUT_MS || 20000);

export const aiConfigured = () => Boolean(URL_BASE);

/** The one deterministic request shape accepted by RAG's /chat route. */
export function chatPrompt(payload) {
  if (typeof payload?.user_query !== 'string' || !payload.user_query.trim()) {
    throw new Error('AI chat request has no patient message');
  }

  return {
    ...(payload.session_id ? { session_id: String(payload.session_id) } : {}),
    user_query: payload.user_query.trim(),
    hospitals: Array.isArray(payload.hospitals) ? payload.hospitals : [],
  };
}

/** Convert the /chat response at one boundary; nothing else needs its shape. */
export function normaliseChatResponse(raw, requestId, requestHospitals = []) {
  if (!raw || typeof raw !== 'object') throw new Error('AI chat returned an invalid response');

  if (raw.response_type === 'mcq' && raw.content && typeof raw.content === 'object') {
    const { question, options } = raw.content;
    if (typeof question !== 'string' || !question.trim() || !Array.isArray(options)) {
      throw new Error('AI chat returned an invalid multiple-choice question');
    }
    return {
      request_id: requestId,
      status: 'needs_more_info',
      reply: question,
      follow_up_questions: [{ id: 'q1', question, options, multi: false }],
    };
  }

  if (raw.response_type === 'text' && typeof raw.content === 'string' && raw.content.trim()) {
    const result = { request_id: requestId, status: 'ok', reply: raw.content };
    if (raw.report && typeof raw.report === 'object') {
      const score = Number(raw.urgency_score ?? raw.report.urgency_score);
      const urgency = Number.isFinite(score)
        ? score >= 80 ? 1 : score >= 60 ? 2 : score >= 40 ? 3 : score >= 20 ? 4 : 5
        : null;
      const symptoms = Array.isArray(raw.report.symptoms_described)
        ? raw.report.symptoms_described.map((name) => ({ name }))
        : [];
      result.chief_complaint = raw.report.symptoms_described?.slice(0, 3).join(', ') || null;
      result.symptoms = symptoms;
      result.specialty = typeof raw.report.recommended_specialty === 'string'
        ? raw.report.recommended_specialty.toLowerCase().trim().replace(/\s+/g, '_')
        : null;
      if (typeof raw.report.recommended_hospital_id === 'string') {
        const hospital = requestHospitals.find((item) => item.id === raw.report.recommended_hospital_id);
        if (hospital) {
          result.suggested_hospitals = [{
            hospital_id: hospital.id,
            name: hospital.name,
            distance_km: hospital.distance_km ?? null,
            reason: result.specialty
              ? `Has a ${result.specialty.replace(/_/g, ' ')} department.`
              : 'Selected by the triage assistant.',
          }];
        }
      }
      result.urgency = urgency;
      result.red_flag = false;
      result.summary = raw.report.rationale || null;
      result.clinical_note = Array.isArray(raw.report.possible_diagnosis)
        ? raw.report.possible_diagnosis.join('; ')
        : null;
      result.confidence = raw.report.confidence_score ?? null;
      result.sources = [];
    }
    return result;
  }

  throw new Error('AI chat returned an unknown response type');
}

// stubTriage() returns invented symptoms, an invented specialty and an invented
// urgency. It is labelled placeholder text in a demo; in front of real patients
// it is a machine handing out clinical-looking advice nobody wrote. Refuse to
// start rather than let a production deploy fall back to it silently.
if (!URL_BASE && process.env.NODE_ENV === 'production') {
  throw new Error(
    'AI_SERVICE_URL must be set in production -- without it triage answers come from ' +
    'the placeholder stub, which invents symptoms, specialty and urgency.',
  );
}

/**
 * @returns {Promise<{source:'stub'|'http', pending:boolean, result:object|null}>}
 *   pending=true means "accepted, answer will arrive on the callback".
 */
export async function requestChat(payload) {
  if (!URL_BASE) return { source: 'stub', pending: false, result: stubTriage(payload) };

  const res = await fetch(`${URL_BASE}/chat`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      ...(TOKEN ? { authorization: `Bearer ${TOKEN}` } : {}),
    },
    body: JSON.stringify(chatPrompt(payload)),
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });

  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`ai service ${res.status}: ${text.slice(0, 300)}`);
  }
  return {
    source: 'http',
    pending: false,
    result: normaliseChatResponse(await res.json(), payload?.request_id, payload?.hospitals),
  };
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
