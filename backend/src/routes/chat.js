/**
 * Two chat surfaces, one table. appfeature.md wants the patient to always know
 * who they are talking to, so a conversation is either:
 *   kind='ai'        -> the triage assistant (answers come from the AI seam)
 *   kind='care_team' -> real people at a hospital (doctors / front desk)
 *
 * Mounted at /conversations. Delivery is plain polling:
 * GET /conversations/:id/messages?after=<iso>. No sockets, no push
 * infrastructure. ponytail: swap in SSE if the poll interval ever shows up in
 * battery or DB load numbers.
 */
import { Router } from 'express';
import { many, one, query } from '../lib/db.js';
import { requireAuth, staffHospitalId } from '../lib/auth.js';
import { bad, enumOf, forbidden, isoTimestamp, notFound, str, uuid } from '../lib/http.js';
import { storeFile, upload } from '../lib/upload.js';
import { runTriage } from '../lib/triage.js';
import { audit } from '../lib/audit.js';

const router = Router();

/** Sorts before every real uuid, so `after` with no `after_id` starts at that instant. */
const ZERO_UUID = '00000000-0000-0000-0000-000000000000';
router.use(requireAuth);

/** Throws unless the caller may see this conversation. Returns {conversation, canPost}. */
async function access(user, conversationId) {
  const c = await one('select * from conversations where id = $1', [uuid(conversationId)]);
  if (!c) throw notFound('conversation');

  if (user.role === 'patient') {
    if (c.patient_id !== user.id) throw forbidden('not your conversation');
    return { conversation: c, canPost: true };
  }

  const hospitalId = await staffHospitalId(user);
  if (c.kind === 'care_team') {
    if (c.hospital_id !== hospitalId) throw forbidden('this thread belongs to another hospital');
    return { conversation: c, canPost: user.role === 'doctor' };
  }

  // Staff may read a patient's triage thread only while that patient is theirs.
  const linked = await one(
    'select 1 from visits where patient_id = $1 and hospital_id = $2 limit 1',
    [c.patient_id, hospitalId],
  );
  if (!linked) throw forbidden('this patient has no visit at your hospital');
  return { conversation: c, canPost: false };
}

router.get('/', async (req, res) => {
  if (req.user.role === 'patient') {
    return res.json(await many(
      `select c.*, h.name as hospital_name,
              (select body from messages m where m.conversation_id = c.id
                order by m.created_at desc limit 1) as last_message
         from conversations c
         left join hospitals h on h.id = c.hospital_id
        where c.patient_id = $1 order by c.last_message_at desc`,
      [req.user.id]));
  }
  const hospitalId = await staffHospitalId(req.user);
  res.json(await many(
    `select c.*, u.full_name as patient_name,
            (select body from messages m where m.conversation_id = c.id
              order by m.created_at desc limit 1) as last_message
       from conversations c join users u on u.id = c.patient_id
      where c.kind = 'care_team' and c.hospital_id = $1
      order by c.last_message_at desc`,
    [hospitalId]));
});

/** Patients open threads. One 'ai' thread is reused by default; care_team needs a hospital. */
router.post('/', async (req, res) => {
  if (req.user.role !== 'patient') throw forbidden('only patients start conversations');
  const kind = enumOf(req.body, 'kind', ['ai', 'care_team'], { required: true });
  const hospitalId = req.body?.hospital_id ? uuid(req.body.hospital_id, 'hospital_id') : null;
  if (kind === 'care_team' && !hospitalId) throw bad('hospital_id is required for a care_team thread');

  if (kind === 'ai' && !req.body?.force_new) {
    const existing = await one(
      `select * from conversations where patient_id = $1 and kind = 'ai'
        order by last_message_at desc limit 1`,
      [req.user.id],
    );
    if (existing) return res.json(existing);
  }

  const title = str(req.body, 'title', { max: 120 }) ?? (kind === 'ai' ? 'Triage assistant' : 'Care team');
  const c = await one(
    `insert into conversations (patient_id, kind, hospital_id, title) values ($1,$2,$3,$4) returning *`,
    [req.user.id, kind, hospitalId, title],
  );

  if (kind === 'ai') {
    await insert(c.id, {
      sender_role: 'ai',
      kind: 'text',
      body: 'Hello. Tell me what is bothering you, in whichever language you are comfortable with.',
    });
  }
  res.status(201).json(c);
});

router.get('/:id', async (req, res) => {
  const { conversation, canPost } = await access(req.user, req.params.id);
  const patient = await one('select id, full_name from users where id = $1', [conversation.patient_id]);
  const hospital = conversation.hospital_id
    ? await one('select id, name from hospitals where id = $1', [conversation.hospital_id])
    : null;
  res.json({ ...conversation, can_post: canPost, patient, hospital });
});

/**
 * ?after=<iso>&after_id=<uuid> for incremental polling; ?limit= caps the page.
 *
 * The cursor is a keyset on (created_at, id), not a bare timestamp. now() is the
 * transaction clock, so every message applyTriageResult writes — reply, MCQs,
 * report, hospital suggestions, status — carries the same created_at down to the
 * microsecond. With a timestamp alone, a page boundary landing inside one of
 * those groups either drops its tail forever (strict >) or re-sends it on every
 * poll (>=). The id breaks the tie and makes the order deterministic.
 *
 * created_at goes out at full precision because it is half of the cursor: a JS
 * Date round-trip would truncate it to milliseconds and the cursor would no
 * longer match the row it came from.
 */
router.get('/:id/messages', async (req, res) => {
  const { conversation } = await access(req.user, req.params.id);
  const after = req.query.after ? isoTimestamp(req.query.after, 'after') : null;
  const afterId = req.query.after_id ? uuid(req.query.after_id, 'after_id') : ZERO_UUID;
  const limit = Math.min(Math.max(Number(req.query.limit) || 200, 1), 500);

  const [rows, pending] = await Promise.all([
    many(
      `select m.id, m.sender_role, m.sender_user_id, m.kind, m.body, m.payload, m.file_id,
              to_char(m.created_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') as created_at,
              u.full_name as sender_name
         from messages m left join users u on u.id = m.sender_user_id
        where m.conversation_id = $1
          and ($2::timestamptz is null or (m.created_at, m.id) > ($2::timestamptz, $3::uuid))
        order by m.created_at, m.id
        limit $4`,
      [conversation.id, after, afterId, limit],
    ),
    // Anything still being worked on, so the app can show its "thinking" state.
    one(
      `select count(*)::int as n from triage_requests
        where conversation_id = $1 and status = 'pending'`,
      [conversation.id],
    ),
  ]);
  res.json({ messages: rows.map(withFileUrl), triage_pending: pending.n > 0 });
});

const withFileUrl = (m) => (m.file_id ? { ...m, file_url: `/files/${m.file_id}` } : m);

const insert = (conversationId, m) =>
  one(
    `insert into messages (conversation_id, sender_role, sender_user_id, kind, body, payload, file_id)
     values ($1,$2,$3,$4,$5,$6,$7) returning *`,
    [
      conversationId, m.sender_role, m.sender_user_id ?? null, m.kind ?? 'text',
      m.body ?? null, m.payload ? JSON.stringify(m.payload) : null, m.file_id ?? null,
    ],
  );

async function afterPost(conversation, { triggerTriage }) {
  await query('update conversations set last_message_at = now() where id = $1', [conversation.id]);
  if (!triggerTriage) return false;
  // Fire and forget: the client polls for the answer, so a slow model never
  // blocks the send. Failures land in the transcript as a 'status' message.
  runTriage({ conversationId: conversation.id, patientId: conversation.patient_id })
    .catch((err) => console.error('[chat] triage error', err.message));
  return true;
}

router.post('/:id/messages', async (req, res) => {
  const { conversation, canPost } = await access(req.user, req.params.id);
  if (!canPost) throw forbidden('you cannot post in this conversation');

  const body = str(req.body, 'body', { required: true, max: 4000 });
  const language = str(req.body, 'language', { max: 12 });
  if (language && req.user.role === 'patient') {
    await query('update patients set language = $2, updated_at = now() where user_id = $1', [
      req.user.id, language,
    ]);
  }

  const senderRole = req.user.role === 'patient' ? 'patient' : 'doctor';
  const message = await insert(conversation.id, {
    sender_role: senderRole,
    sender_user_id: req.user.id,
    kind: 'text',
    body,
  });

  const pending = await afterPost(conversation, {
    triggerTriage: conversation.kind === 'ai' && senderRole === 'patient',
  });
  res.status(201).json({ message, triage_pending: pending });
});

/**
 * Image / audio attachment in one round trip: multipart with `file`, optional
 * `body` caption. Voice input is a mock button in the MVP, but the route accepts
 * audio so wiring real speech-to-text later needs no client change.
 */
router.post('/:id/attachments', upload.single('file'), async (req, res) => {
  const { conversation, canPost } = await access(req.user, req.params.id);
  if (!canPost) throw forbidden('you cannot post in this conversation');

  const file = await storeFile(req.user.id, req.file);
  const kind = file.mime.startsWith('audio/') ? 'audio' : 'image';
  const senderRole = req.user.role === 'patient' ? 'patient' : 'doctor';
  const message = await insert(conversation.id, {
    sender_role: senderRole,
    sender_user_id: req.user.id,
    kind,
    body: str(req.body, 'body', { max: 500 }),
    file_id: file.id,
  });

  await afterPost(conversation, {
    triggerTriage: conversation.kind === 'ai' && senderRole === 'patient',
  });
  res.status(201).json(withFileUrl(message));
});

/**
 * Answers to the MCQs the assistant asked. Stored as one 'mcq_answer' message so
 * the whole exchange stays in the transcript the AI side reads back.
 */
router.post('/:id/mcq-answer', async (req, res) => {
  const { conversation, canPost } = await access(req.user, req.params.id);
  if (!canPost || req.user.role !== 'patient') throw forbidden('only the patient answers these');

  const questionMessageId = uuid(req.body?.message_id, 'message_id');
  const answers = req.body?.answers;
  if (!answers || typeof answers !== 'object' || Array.isArray(answers))
    throw bad('answers must be an object of question_id -> answer');

  const asked = await one(
    `select payload from messages where id = $1 and conversation_id = $2 and kind = 'mcq'`,
    [questionMessageId, conversation.id],
  );
  if (!asked) throw notFound('question set');

  const questions = asked.payload?.questions ?? [];
  const summary = questions
    .map((q) => (answers[q.id] === undefined ? null : `${q.question} — ${[answers[q.id]].flat().join(', ')}`))
    .filter(Boolean)
    .join('\n');
  if (!summary) throw bad('none of the answers match the questions that were asked');

  const message = await insert(conversation.id, {
    sender_role: 'patient',
    sender_user_id: req.user.id,
    kind: 'mcq_answer',
    body: summary,
    payload: { in_reply_to: questionMessageId, answers },
  });

  audit(req.user.id, 'chat.mcq_answered', 'message', message.id, { answers });
  await afterPost(conversation, { triggerTriage: conversation.kind === 'ai' });
  res.status(201).json({ message, triage_pending: true });
});

export default router;
