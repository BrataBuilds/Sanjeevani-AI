/**
 * Orchestration around the AI seam: build the request payload, hand it to
 * lib/ai.js, then persist whatever comes back and turn it into chat messages and
 * a queue entry. All triage *decisions* come from the AI side; this file only
 * stores and presents them.
 */
import { many, one, query, tx } from './db.js';
import { ageFrom } from './http.js';
import { audit } from './audit.js';
import { normaliseTriage, requestTriage } from './ai.js';

const R = 6371; // km
export function distanceKm(a, b) {
  if ([a?.lat, a?.lng, b?.lat, b?.lng].some((v) => v === null || v === undefined)) return null;
  const rad = (d) => (d * Math.PI) / 180;
  const dLat = rad(b.lat - a.lat);
  const dLng = rad(b.lng - a.lng);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return Math.round(2 * R * Math.asin(Math.sqrt(h)) * 10) / 10;
}

/** Hospitals with their specialties, sorted by distance from the patient. */
export async function hospitalsNear(patient) {
  const rows = await many(
    `select h.id, h.name, h.address, h.city, h.phone, h.lat, h.lng,
            coalesce(array_agg(d.specialty) filter (where d.specialty is not null), '{}') as specialties
       from hospitals h
       left join departments d on d.hospital_id = h.id
      group by h.id
      order by h.name`,
  );
  return rows
    .map((h) => ({ ...h, distance_km: distanceKm(patient, h) }))
    .sort((a, b) => (a.distance_km ?? 1e9) - (b.distance_km ?? 1e9));
}

async function buildPayload(requestId, conversationId, patientId) {
  const patient = await one(
    `select p.*, u.full_name, u.email from patients p
       join users u on u.id = p.user_id where p.user_id = $1`,
    [patientId],
  );
  const conditions = await many(
    'select kind, label, notes from patient_conditions where patient_id = $1',
    [patientId],
  );
  const messages = await many(
    `select sender_role as role, kind, body, payload, file_id, created_at
       from messages where conversation_id = $1 order by created_at`,
    [conversationId],
  );
  const hospitals = await hospitalsNear(patient);

  return {
    request_id: requestId,
    // Where an async service should POST its answer.
    callback_url: `${(process.env.PUBLIC_API_URL || 'http://localhost:4000').replace(/\/$/, '')}/ai/triage-callback`,
    language: patient.language,
    patient: {
      id: patient.user_id,
      age: ageFrom(patient.dob),
      gender: patient.gender,
      blood_type: patient.blood_type,
      known_conditions: conditions,
      location: { lat: patient.lat, lng: patient.lng },
    },
    conversation: { id: conversationId, messages },
    // Attachments are referenced, not inlined — GET /files/:id with a service token.
    attachments: messages
      .filter((m) => m.file_id)
      .map((m) => ({ file_id: m.file_id, kind: m.kind, url: `/files/${m.file_id}` })),
    hospitals: hospitals.map(({ id, name, specialties, lat, lng, distance_km }) => ({
      id, name, specialties, lat, lng, distance_km,
    })),
  };
}

/**
 * Fire one triage round for a conversation. Never throws into the request path:
 * on failure it marks the request failed and drops a 'status' message in the
 * chat so the patient sees something instead of silence.
 */
export async function runTriage({ conversationId, patientId }) {
  const req = await one(
    `insert into triage_requests (conversation_id, patient_id, request)
     values ($1, $2, '{}'::jsonb) returning id`,
    [conversationId, patientId],
  );

  let payload;
  try {
    payload = await buildPayload(req.id, conversationId, patientId);
    await query('update triage_requests set request = $2 where id = $1', [
      req.id,
      JSON.stringify(payload),
    ]);
  } catch (err) {
    await failRequest(req.id, err.message);
    return { requestId: req.id, pending: false, failed: true };
  }

  try {
    const { source, pending, result } = await requestTriage(payload);
    await query('update triage_requests set source = $2 where id = $1', [req.id, source]);
    if (pending) return { requestId: req.id, pending: true };
    await applyTriageResult(req.id, result);
    return { requestId: req.id, pending: false };
  } catch (err) {
    console.error('[triage] failed', err.message);
    await failRequest(req.id, err.message);
    return { requestId: req.id, pending: false, failed: true };
  }
}

async function failRequest(requestId, message) {
  await query(
    `update triage_requests set status = 'failed', error = $2, completed_at = now() where id = $1`,
    [requestId, message?.slice(0, 500) ?? 'unknown error'],
  );
  const req = await one('select conversation_id from triage_requests where id = $1', [requestId]);
  if (req) {
    await insertMessage(query, req.conversation_id, {
      sender_role: 'system',
      kind: 'status',
      body: 'The assistant is unavailable right now. Please try again, or talk to the hospital directly.',
      payload: { state: 'triage_failed' },
    });
  }
  await audit(null, 'triage.failed', 'triage_request', requestId, { error: message });
}

const insertMessage = (q, conversationId, m) =>
  q(
    `insert into messages (conversation_id, sender_role, sender_user_id, kind, body, payload, file_id)
     values ($1, $2, $3, $4, $5, $6, $7) returning *`,
    [
      conversationId,
      m.sender_role,
      m.sender_user_id ?? null,
      m.kind ?? 'text',
      m.body ?? null,
      m.payload ? JSON.stringify(m.payload) : null,
      m.file_id ?? null,
    ],
  );

/**
 * Persist an AI answer and fan it out into the chat. Called both from runTriage
 * (synchronous path) and from POST /ai/triage-callback (asynchronous path).
 */
export async function applyTriageResult(requestId, rawResult) {
  const req = await one(
    `select id, conversation_id, patient_id, status from triage_requests where id = $1`,
    [requestId],
  );
  if (!req) throw new Error(`unknown triage request ${requestId}`);
  if (req.status === 'done') return { alreadyApplied: true };

  const t = normaliseTriage(rawResult);

  return tx(async (client) => {
    const q = (sql, params) => client.query(sql, params);

    const result = (
      await q(
        `insert into triage_results
           (triage_request_id, patient_id, chief_complaint, symptoms, specialty, urgency,
            red_flag, summary, clinical_note, sources, suggested_hospitals,
            follow_up_questions, confidence, raw)
         values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14)
         returning *`,
        [
          requestId,
          req.patient_id,
          t.chief_complaint,
          t.symptoms ? JSON.stringify(t.symptoms) : null,
          t.specialty,
          t.urgency,
          t.red_flag,
          t.summary,
          t.clinical_note,
          t.sources ? JSON.stringify(t.sources) : null,
          t.suggested_hospitals ? JSON.stringify(t.suggested_hospitals) : null,
          t.follow_up_questions ? JSON.stringify(t.follow_up_questions) : null,
          t.confidence,
          JSON.stringify(t.raw),
        ],
      )
    ).rows[0];

    await q(`update triage_requests set status = 'done', completed_at = now() where id = $1`, [
      requestId,
    ]);

    if (t.reply) {
      await insertMessage(q, req.conversation_id, {
        sender_role: 'ai',
        kind: 'text',
        body: t.reply,
      });
    }

    if (t.follow_up_questions?.length) {
      await insertMessage(q, req.conversation_id, {
        sender_role: 'ai',
        kind: 'mcq',
        body: 'A few quick questions',
        payload: { triage_result_id: result.id, questions: t.follow_up_questions },
      });
    }

    if (t.summary || t.specialty || t.red_flag) {
      await insertMessage(q, req.conversation_id, {
        sender_role: 'ai',
        kind: 'report',
        body: t.summary || 'Preliminary summary ready',
        payload: {
          triage_result_id: result.id,
          chief_complaint: t.chief_complaint,
          symptoms: t.symptoms,
          specialty: t.specialty,
          urgency: t.urgency,
          red_flag: t.red_flag,
          summary: t.summary,
          confidence: t.confidence,
          sources: t.sources,
        },
      });
    }

    if (t.suggested_hospitals?.length) {
      await insertMessage(q, req.conversation_id, {
        sender_role: 'ai',
        kind: 'hospital_suggestion',
        body: 'Suggested facilities',
        payload: { hospitals: t.suggested_hospitals },
      });
    }

    // A specialty (or a red flag) is enough to put the patient in a queue.
    let visit = null;
    if (t.specialty || t.red_flag) {
      visit = await createVisit(client, {
        patientId: req.patient_id,
        specialty: t.red_flag ? 'emergency' : t.specialty,
        urgency: t.red_flag ? 1 : (t.urgency ?? 4),
        triageResultId: result.id,
        suggested: t.suggested_hospitals,
        reason: t.chief_complaint,
      });
      if (visit) {
        await insertMessage(q, req.conversation_id, {
          sender_role: 'system',
          kind: 'status',
          body: `Token #${visit.token_no} · ${visit.department_name ?? 'Front desk'}` +
            (visit.doctor_name ? ` · ${visit.doctor_name}` : '') +
            ` · ${visit.hospital_name}`,
          payload: {
            visit_id: visit.id,
            token_no: visit.token_no,
            state: visit.status,
            hospital: visit.hospital_name,
            department: visit.department_name,
            doctor: visit.doctor_name,
            urgency: visit.urgency,
            red_flag: t.red_flag,
          },
        });
      }
    }

    await q('update conversations set last_message_at = now() where id = $1', [req.conversation_id]);

    await audit(null, 'triage.result_applied', 'triage_result', result.id, {
      specialty: t.specialty,
      urgency: t.urgency,
      red_flag: t.red_flag,
      visit_id: visit?.id ?? null,
    }, visit?.hospital_id ?? null);

    return { result, visit };
  });
}

/**
 * Put the patient in a queue. Hospital preference order: whatever the AI
 * suggested first, then the patient's preferred hospital, then the nearest one.
 */
async function createVisit(client, { patientId, specialty, urgency, triageResultId, suggested, reason }) {
  const patient = (
    await client.query('select lat, lng from patients where user_id = $1', [patientId])
  ).rows[0];

  const suggestedId = suggested?.find((h) => h?.hospital_id)?.hospital_id ?? null;
  const preferred = (
    await client.query(
      'select hospital_id from patient_preferred_hospitals where patient_id = $1 limit 1',
      [patientId],
    )
  ).rows[0]?.hospital_id ?? null;

  const all = (
    await client.query('select id, name, lat, lng from hospitals')
  ).rows.map((h) => ({ ...h, distance_km: distanceKm(patient, h) }));
  if (!all.length) return null;

  const nearest = [...all].sort((a, b) => (a.distance_km ?? 1e9) - (b.distance_km ?? 1e9))[0];
  const hospital =
    all.find((h) => h.id === suggestedId) || all.find((h) => h.id === preferred) || nearest;

  const dept = (
    await client.query(
      `select id, name from departments
        where hospital_id = $1 and specialty = any($2::text[])
        order by array_position($2::text[], specialty) limit 1`,
      [hospital.id, [specialty, 'general_medicine'].filter(Boolean)],
    )
  ).rows[0] ?? null;

  const doctor = dept
    ? (
        await client.query(
          `select d.user_id, u.full_name from doctors d
             join users u on u.id = d.user_id
            where d.department_id = $1 and d.is_available and u.is_active
            order by u.full_name limit 1`,
          [dept.id],
        )
      ).rows[0] ?? null
    : null;

  // ponytail: max()+1 can collide under simultaneous intake. A per-hospital
  // sequence or an advisory lock is the fix if two kiosks ever register at once.
  const nextToken =
    (
      await client.query(
        `select coalesce(max(token_no), 0) + 1 as n from visits
          where hospital_id = $1 and token_date = current_date`,
        [hospital.id],
      )
    ).rows[0].n;

  const visit = (
    await client.query(
      `insert into visits (patient_id, hospital_id, department_id, doctor_user_id,
                           triage_result_id, token_no, urgency, reason)
       values ($1,$2,$3,$4,$5,$6,$7,$8) returning *`,
      [patientId, hospital.id, dept?.id ?? null, doctor?.user_id ?? null, triageResultId,
       nextToken, urgency, reason ?? null],
    )
  ).rows[0];

  return {
    ...visit,
    hospital_name: hospital.name,
    department_name: dept?.name ?? null,
    doctor_name: doctor?.full_name ?? null,
  };
}
