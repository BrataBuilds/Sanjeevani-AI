/**
 * Doctor-side dashboard API. Design_doc.md §3: see the preliminary report before
 * the consult, manage the queue, override urgency.
 *
 * Human-in-the-loop is the point — every override is written to audit_log.
 */
import { Router } from 'express';
import { many, one, query } from '../lib/db.js';
import { requireAuth, requireRole, staffHospitalId } from '../lib/auth.js';
import { ageFrom, bad, enumOf, notFound, num, str, uuid } from '../lib/http.js';
import { audit } from '../lib/audit.js';

const router = Router();
router.use(requireAuth, requireRole('doctor'));

const VISIT_STATUSES = ['waiting', 'in_consult', 'done', 'referred', 'cancelled'];

/**
 * The queue. Most urgent first, then longest waiting — the ordering Design_doc.md
 * §1 says today's first-come-first-served queues get wrong.
 * ?scope=mine (default) | department | hospital, ?status=, ?date=
 */
router.get('/queue', async (req, res) => {
  const hospitalId = await staffHospitalId(req.user);
  const me = await one('select department_id from doctors where user_id = $1', [req.user.id]);
  const scope = enumOf(req.query, 'scope', ['mine', 'department', 'hospital']) ?? 'mine';
  const status = req.query.status ? enumOf(req.query, 'status', VISIT_STATUSES) : null;
  const date = req.query.date ? str(req.query, 'date', { max: 10 }) : null;

  const rows = await many(
    `select v.id, v.token_no, v.token_date, v.status, v.urgency, v.urgency_overridden,
            v.reason, v.created_at, v.updated_at,
            u.id as patient_id, u.full_name as patient_name,
            p.dob, p.gender, p.blood_type, p.profile_file_id,
            dep.name as department_name,
            du.full_name as doctor_name,
            tr.id as triage_result_id, tr.specialty, tr.red_flag, tr.summary,
            tr.clinical_note, tr.chief_complaint, tr.confidence
       from visits v
       join users u on u.id = v.patient_id
       join patients p on p.user_id = v.patient_id
       left join departments dep on dep.id = v.department_id
       left join users du on du.id = v.doctor_user_id
       left join triage_results tr on tr.id = v.triage_result_id
      where v.hospital_id = $1
        and ($2::uuid is null or v.doctor_user_id = $2)
        and ($3::uuid is null or v.department_id = $3)
        and ($4::text is null or v.status = $4)
        and v.token_date = coalesce($5::date, current_date)
      order by (v.status = 'in_consult') desc, v.urgency asc, v.created_at asc`,
    [
      hospitalId,
      scope === 'mine' ? req.user.id : null,
      scope === 'department' ? me?.department_id ?? null : null,
      status,
      date,
    ],
  );

  res.json(rows.map((v) => ({
    ...v,
    age: ageFrom(v.dob),
    dob: undefined,
    patient_photo_url: v.profile_file_id ? `/files/${v.profile_file_id}` : null,
    profile_file_id: undefined,
  })));
});

/** Everything the doctor needs before walking into the room. */
router.get('/visits/:id', async (req, res) => {
  const hospitalId = await staffHospitalId(req.user);
  const visit = await one(
    `select v.*, u.full_name as patient_name, u.email as patient_email,
            dep.name as department_name, h.name as hospital_name
       from visits v
       join users u on u.id = v.patient_id
       join hospitals h on h.id = v.hospital_id
       left join departments dep on dep.id = v.department_id
      where v.id = $1 and v.hospital_id = $2`,
    [uuid(req.params.id), hospitalId],
  );
  if (!visit) throw notFound('visit');

  const [patient, conditions, relatives, documents, triage, aiThread] = await Promise.all([
    one('select * from patients where user_id = $1', [visit.patient_id]),
    many('select kind, label, notes from patient_conditions where patient_id = $1', [visit.patient_id]),
    many('select name, contact, relation, notify from patient_relatives where patient_id = $1', [visit.patient_id]),
    many(
      `select d.id, d.label, d.description, d.created_at, f.id as file_id, f.mime, f.size_bytes
         from medical_documents d join files f on f.id = d.file_id
        where d.patient_id = $1 order by d.created_at desc`,
      [visit.patient_id],
    ),
    visit.triage_result_id
      ? one('select * from triage_results where id = $1', [visit.triage_result_id])
      : null,
    one(`select id from conversations where patient_id = $1 and kind = 'ai'
          order by last_message_at desc limit 1`, [visit.patient_id]),
  ]);

  const { app_lock_pin_hash, ...safePatient } = patient ?? {};
  res.json({
    visit,
    patient: {
      ...safePatient,
      full_name: visit.patient_name,
      email: visit.patient_email,
      age: ageFrom(patient?.dob),
      photo_url: patient?.profile_file_id ? `/files/${patient.profile_file_id}` : null,
    },
    conditions,
    relatives,
    documents: documents.map((d) => ({ ...d, url: `/files/${d.file_id}` })),
    triage,
    ai_conversation_id: aiThread?.id ?? null,
  });
});

/**
 * Advance the queue, override urgency, leave notes. The AI suggestion is never
 * final — this endpoint is what makes that true.
 */
router.patch('/visits/:id', async (req, res) => {
  const hospitalId = await staffHospitalId(req.user);
  const id = uuid(req.params.id);
  const before = await one('select * from visits where id = $1 and hospital_id = $2', [id, hospitalId]);
  if (!before) throw notFound('visit');

  const status = req.body?.status === undefined ? undefined : enumOf(req.body, 'status', VISIT_STATUSES);
  const urgency = req.body?.urgency === undefined ? undefined : num(req.body, 'urgency', { min: 1, max: 5 });
  const notes = req.body?.doctor_notes === undefined ? undefined : str(req.body, 'doctor_notes', { max: 4000 });
  const claim = req.body?.claim === true;
  if (status === undefined && urgency === undefined && notes === undefined && !claim)
    throw bad('nothing to update');

  const after = await one(
    `update visits set
       status = coalesce($3, status),
       urgency = coalesce($4, urgency),
       urgency_overridden = urgency_overridden or ($4 is not null and $4 <> urgency),
       doctor_notes = coalesce($5, doctor_notes),
       doctor_user_id = case when $6 then $7 else doctor_user_id end,
       updated_at = now()
     where id = $1 and hospital_id = $2 returning *`,
    [id, hospitalId, status ?? null, urgency ?? null, notes ?? null, claim, req.user.id],
  );

  audit(req.user.id, 'visit.updated', 'visit', id, {
    status: status ?? undefined,
    urgency_from: urgency !== undefined && urgency !== before.urgency ? before.urgency : undefined,
    urgency_to: urgency !== undefined && urgency !== before.urgency ? urgency : undefined,
    ai_urgency: before.urgency,
    notes_changed: notes !== undefined,
    claimed: claim || undefined,
  });

  res.json(after);
});

/** Open (or reuse) the human chat thread with this patient. */
router.post('/patients/:id/conversation', async (req, res) => {
  const hospitalId = await staffHospitalId(req.user);
  const patientId = uuid(req.params.id, 'patient id');
  const linked = await one(
    'select 1 from visits where patient_id = $1 and hospital_id = $2 limit 1',
    [patientId, hospitalId],
  );
  if (!linked) throw notFound('a visit for this patient at your hospital');

  const existing = await one(
    `select * from conversations where patient_id = $1 and kind = 'care_team' and hospital_id = $2
      order by last_message_at desc limit 1`,
    [patientId, hospitalId],
  );
  if (existing) return res.json(existing);

  const created = await one(
    `insert into conversations (patient_id, kind, hospital_id, title)
     values ($1, 'care_team', $2, $3) returning *`,
    [patientId, hospitalId, 'Care team'],
  );
  await query(
    `insert into messages (conversation_id, sender_role, sender_user_id, kind, body)
     values ($1, 'system', $2, 'status', $3)`,
    [created.id, req.user.id, `${req.user.full_name} from the care team joined this chat.`],
  );
  res.status(201).json(created);
});

export default router;
