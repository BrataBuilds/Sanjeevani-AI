import { Router } from 'express';
import { many, one, query, tx } from '../lib/db.js';
import { requireAuth, requireRole } from '../lib/auth.js';
import { ageFrom, bad, bool, enumOf, notFound, num, str, uuid } from '../lib/http.js';
import { storeFile, upload } from '../lib/upload.js';
import { audit } from '../lib/audit.js';

const router = Router();
router.use(requireAuth, requireRole('patient'));

const GENDERS = ['male', 'female', 'other', 'prefer_not_to_say'];
const CONDITION_KINDS = ['disease', 'allergy', 'genetic'];

async function profileOf(userId) {
  const p = await one(
    `select p.*, u.full_name, u.email from patients p
       join users u on u.id = p.user_id where p.user_id = $1`,
    [userId],
  );
  if (!p) throw notFound('patient profile');
  const [conditions, relatives, preferred] = await Promise.all([
    many('select id, kind, label, notes from patient_conditions where patient_id = $1 order by created_at', [userId]),
    many('select id, name, contact, relation, notify from patient_relatives where patient_id = $1 order by created_at', [userId]),
    many(
      `select h.id, h.name, h.city from patient_preferred_hospitals ph
         join hospitals h on h.id = ph.hospital_id where ph.patient_id = $1`,
      [userId],
    ),
  ]);
  const { app_lock_pin_hash, ...rest } = p;
  return {
    ...rest,
    age: ageFrom(p.dob),
    app_lock_set: Boolean(app_lock_pin_hash),
    conditions,
    relatives,
    preferred_hospitals: preferred,
  };
}

router.get('/profile', async (req, res) => res.json(await profileOf(req.user.id)));

/**
 * Whole-profile save. The app collects everything on one setup flow, so a single
 * PUT is less round-tripping than a field-by-field PATCH. Absent keys are left alone.
 */
router.put('/profile', async (req, res) => {
  const b = req.body ?? {};
  const fullName = str(b, 'full_name', { max: 120 });
  const fields = {
    dob: b.dob === undefined ? undefined : (str(b, 'dob', { max: 20 }) ?? null),
    gender: b.gender === undefined ? undefined : enumOf(b, 'gender', GENDERS),
    blood_type: b.blood_type === undefined ? undefined : str(b, 'blood_type', { max: 8 }),
    phone: b.phone === undefined ? undefined : str(b, 'phone', { max: 24 }),
    address: b.address === undefined ? undefined : str(b, 'address', { max: 400 }),
    lat: b.lat === undefined ? undefined : num(b, 'lat', { min: -90, max: 90 }),
    lng: b.lng === undefined ? undefined : num(b, 'lng', { min: -180, max: 180 }),
    insurance_provider: b.insurance_provider === undefined ? undefined : str(b, 'insurance_provider', { max: 120 }),
    policy_number: b.policy_number === undefined ? undefined : str(b, 'policy_number', { max: 80 }),
    language: b.language === undefined ? undefined : str(b, 'language', { max: 12 }),
    profile_complete: b.profile_complete === undefined ? undefined : bool(b, 'profile_complete'),
  };

  const set = Object.entries(fields).filter(([, v]) => v !== undefined);
  await tx(async (c) => {
    if (fullName) await c.query('update users set full_name = $2 where id = $1', [req.user.id, fullName]);
    if (set.length) {
      const assignments = set.map(([k], i) => `${k} = $${i + 2}`).join(', ');
      await c.query(
        `update patients set ${assignments}, updated_at = now() where user_id = $1`,
        [req.user.id, ...set.map(([, v]) => v)],
      );
    }
  });

  audit(req.user.id, 'patient.profile_updated', 'patient', req.user.id, { fields: set.map(([k]) => k) });
  res.json(await profileOf(req.user.id));
});

router.post('/profile/photo', upload.single('file'), async (req, res) => {
  const file = await storeFile(req.user.id, req.file);
  await query('update patients set profile_file_id = $2, updated_at = now() where user_id = $1', [
    req.user.id, file.id,
  ]);
  res.status(201).json({ ...file, url: `/files/${file.id}` });
});

// ------------------------------------------------------------ conditions

router.get('/conditions', async (req, res) =>
  res.json(await many(
    'select id, kind, label, notes, created_at from patient_conditions where patient_id = $1 order by created_at',
    [req.user.id])));

router.post('/conditions', async (req, res) => {
  const kind = enumOf(req.body, 'kind', CONDITION_KINDS, { required: true });
  const label = str(req.body, 'label', { required: true, max: 200 });
  const notes = str(req.body, 'notes', { max: 500 });
  res.status(201).json(await one(
    `insert into patient_conditions (patient_id, kind, label, notes)
     values ($1,$2,$3,$4) returning id, kind, label, notes, created_at`,
    [req.user.id, kind, label, notes]));
});

router.delete('/conditions/:id', async (req, res) => {
  const row = await one('delete from patient_conditions where id = $1 and patient_id = $2 returning id', [
    uuid(req.params.id), req.user.id,
  ]);
  if (!row) throw notFound('condition');
  res.status(204).end();
});

// ------------------------------------------------------------ relatives

router.get('/relatives', async (req, res) =>
  res.json(await many(
    'select id, name, contact, relation, notify, created_at from patient_relatives where patient_id = $1 order by created_at',
    [req.user.id])));

router.post('/relatives', async (req, res) => {
  const name = str(req.body, 'name', { required: true, max: 120 });
  const contact = str(req.body, 'contact', { required: true, max: 40 });
  const relation = str(req.body, 'relation', { required: true, max: 40 });
  res.status(201).json(await one(
    `insert into patient_relatives (patient_id, name, contact, relation, notify)
     values ($1,$2,$3,$4,$5) returning id, name, contact, relation, notify, created_at`,
    [req.user.id, name, contact, relation, bool(req.body, 'notify', true)]));
});

router.delete('/relatives/:id', async (req, res) => {
  const row = await one('delete from patient_relatives where id = $1 and patient_id = $2 returning id', [
    uuid(req.params.id), req.user.id,
  ]);
  if (!row) throw notFound('relative');
  res.status(204).end();
});

// ------------------------------------------------------------ preferred hospitals

router.put('/preferred-hospitals', async (req, res) => {
  const ids = Array.isArray(req.body?.hospital_ids) ? req.body.hospital_ids.map((v) => uuid(v, 'hospital_id')) : null;
  if (!ids) throw bad('hospital_ids must be an array of uuids');
  await tx(async (c) => {
    await c.query('delete from patient_preferred_hospitals where patient_id = $1', [req.user.id]);
    for (const id of ids) {
      await c.query(
        `insert into patient_preferred_hospitals (patient_id, hospital_id) values ($1,$2)
         on conflict do nothing`,
        [req.user.id, id],
      );
    }
  });
  res.json(await many(
    `select h.id, h.name, h.city from patient_preferred_hospitals ph
       join hospitals h on h.id = ph.hospital_id where ph.patient_id = $1`,
    [req.user.id]));
});

// ------------------------------------------------------------ medical history

router.get('/documents', async (req, res) =>
  res.json(await many(
    `select d.id, d.label, d.description, d.created_at,
            f.id as file_id, f.filename, f.mime, f.size_bytes
       from medical_documents d join files f on f.id = d.file_id
      where d.patient_id = $1 order by d.created_at desc`,
    [req.user.id])));

/** multipart/form-data: file, label, description. Images and scanned PDFs. */
router.post('/documents', upload.single('file'), async (req, res) => {
  const label = str(req.body, 'label', { required: true, max: 120 });
  const description = str(req.body, 'description', { max: 500 });
  const file = await storeFile(req.user.id, req.file);
  const doc = await one(
    `insert into medical_documents (patient_id, file_id, label, description)
     values ($1,$2,$3,$4) returning id, label, description, created_at`,
    [req.user.id, file.id, label, description],
  );
  res.status(201).json({ ...doc, file_id: file.id, mime: file.mime, size_bytes: file.size_bytes, url: `/files/${file.id}` });
});

router.delete('/documents/:id', async (req, res) => {
  const row = await one(
    'delete from medical_documents where id = $1 and patient_id = $2 returning file_id',
    [uuid(req.params.id), req.user.id],
  );
  if (!row) throw notFound('document');
  await query('delete from files where id = $1 and owner_user_id = $2', [row.file_id, req.user.id]);
  res.status(204).end();
});

// ------------------------------------------------------------ aadhaar (UI only)

/**
 * appfeature.md asks for "Aadhaar login verification (UI only)". There is no UIDAI
 * integration here and there must not be one until the compliance work is done:
 * we keep the last four digits for display and flip a flag. Nothing is verified.
 */
router.post('/aadhaar/verify', async (req, res) => {
  const number = str(req.body, 'aadhaar_number', { required: true, max: 20 }).replace(/\D/g, '');
  if (number.length !== 12) throw bad('aadhaar number must be 12 digits');
  // aadhaar_verified stays FALSE. No verifier is wired to this endpoint, and a
  // column that says "verified" is read by staff as a checked identity -- writing
  // true here would put a claim in the database that nothing ever established.
  // The last four digits are what the patient typed, stored as what they typed.
  // Set this to true only from a real UIDAI response.
  await query(
    'update patients set aadhaar_last4 = $2, updated_at = now() where user_id = $1',
    [req.user.id, number.slice(-4)],
  );
  audit(req.user.id, 'patient.aadhaar_recorded', 'patient', req.user.id, { verified: false });
  res.json({
    aadhaar_verified: false,
    aadhaar_last4: number.slice(-4),
    verification_available: false,
    message: 'Number recorded. Identity verification is not connected on this server.',
  });
});

// ------------------------------------------------------------ visits & bills

router.get('/visits', async (req, res) =>
  res.json(await many(
    `select v.id, v.token_no, v.token_date, v.status, v.urgency, v.reason, v.created_at,
            h.name as hospital_name, dep.name as department_name, du.full_name as doctor_name,
            tr.specialty, tr.summary, tr.red_flag
       from visits v
       join hospitals h on h.id = v.hospital_id
       left join departments dep on dep.id = v.department_id
       left join users du on du.id = v.doctor_user_id
       left join triage_results tr on tr.id = v.triage_result_id
      where v.patient_id = $1
      order by v.created_at desc`,
    [req.user.id])));

/**
 * appfeature.md 1.4: "a button to view collected medical bills and info".
 * Billing is Phase 2 in Design_doc.md §6, so there is no bill table yet — this
 * returns the visit ledger the screen can already show, and an empty bill list.
 */
router.get('/bills', async (req, res) => {
  const visits = await many(
    `select v.id, v.token_no, v.token_date, v.status, h.name as hospital_name,
            dep.name as department_name
       from visits v join hospitals h on h.id = v.hospital_id
       left join departments dep on dep.id = v.department_id
      where v.patient_id = $1 order by v.created_at desc`,
    [req.user.id],
  );
  const documents = await many(
    `select d.id, d.label, d.created_at, f.id as file_id, f.mime
       from medical_documents d join files f on f.id = d.file_id
      where d.patient_id = $1 and d.label ilike any (array['%bill%','%invoice%','%receipt%'])
      order by d.created_at desc`,
    [req.user.id],
  );
  res.json({ bills: [], billing_enabled: false, visits, uploaded_bills: documents });
});

export default router;
