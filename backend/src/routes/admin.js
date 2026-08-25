/**
 * Hospital admin API. Design_doc.md §3: patient flow analytics, department load,
 * bottleneck visibility, plus the staff provisioning the rest of the system needs
 * (doctors and admins never self-signup).
 */
import { Router } from 'express';
import { many, one, tx } from '../lib/db.js';
import { hashPassword, requireAuth, requireRole, staffHospitalId } from '../lib/auth.js';
import { ageFrom, bad, bool, email as emailOf, enumOf, notFound, str, uuid } from '../lib/http.js';
import { audit } from '../lib/audit.js';

const router = Router();
router.use(requireAuth, requireRole('admin'));

/** Numbers for the dashboard. All scoped to the admin's own hospital. */
router.get('/overview', async (req, res) => {
  const hospitalId = await staffHospitalId(req.user);
  const days = Math.min(Math.max(Number(req.query.days) || 7, 1), 90);

  const [totals, byStatus, byUrgency, byDepartment, bySpecialty, daily, waitMinutes] =
    await Promise.all([
      one(
        `select
           count(*) filter (where token_date = current_date)::int as today,
           count(*) filter (where status in ('waiting','in_consult') and token_date = current_date)::int as in_queue,
           count(*) filter (where urgency = 1 and token_date = current_date)::int as critical_today,
           count(*)::int as all_time
         from visits where hospital_id = $1`,
        [hospitalId],
      ),
      many(
        `select status, count(*)::int as n from visits
          where hospital_id = $1 and token_date = current_date group by status order by status`,
        [hospitalId],
      ),
      many(
        `select urgency, count(*)::int as n from visits
          where hospital_id = $1 and token_date = current_date group by urgency order by urgency`,
        [hospitalId],
      ),
      many(
        `select coalesce(d.name, 'Unassigned') as department, count(*)::int as n,
                count(*) filter (where v.status in ('waiting','in_consult'))::int as waiting
           from visits v left join departments d on d.id = v.department_id
          where v.hospital_id = $1 and v.token_date = current_date
          group by 1 order by n desc`,
        [hospitalId],
      ),
      many(
        `select coalesce(tr.specialty, 'unrouted') as specialty, count(*)::int as n
           from visits v left join triage_results tr on tr.id = v.triage_result_id
          where v.hospital_id = $1 and v.token_date >= current_date - ($2::int - 1)
          group by 1 order by n desc limit 12`,
        [hospitalId, days],
      ),
      many(
        `select token_date as day, count(*)::int as n,
                count(*) filter (where urgency <= 2)::int as urgent
           from visits
          where hospital_id = $1 and token_date >= current_date - ($2::int - 1)
          group by token_date order by token_date`,
        [hospitalId, days],
      ),
      one(
        `select round(avg(extract(epoch from (updated_at - created_at)) / 60))::int as avg_minutes
           from visits
          where hospital_id = $1 and status in ('done','referred')
            and token_date >= current_date - ($2::int - 1)`,
        [hospitalId, days],
      ),
    ]);

  const staff = await one(
    `select count(*)::int as doctors, count(*) filter (where is_available)::int as available
       from doctors where hospital_id = $1`,
    [hospitalId],
  );

  res.json({
    hospital_id: hospitalId,
    window_days: days,
    totals,
    staff,
    avg_handling_minutes: waitMinutes?.avg_minutes ?? null,
    by_status: byStatus,
    by_urgency: byUrgency,
    by_department: byDepartment,
    by_specialty: bySpecialty,
    daily,
  });
});

/** Full visit list with filters — the bottleneck view. */
router.get('/visits', async (req, res) => {
  const hospitalId = await staffHospitalId(req.user);
  const status = req.query.status
    ? enumOf(req.query, 'status', ['waiting', 'in_consult', 'done', 'referred', 'cancelled'])
    : null;
  const limit = Math.min(Number(req.query.limit) || 100, 500);

  res.json(await many(
    `select v.id, v.token_no, v.token_date, v.status, v.urgency, v.urgency_overridden,
            v.reason, v.created_at, v.updated_at,
            u.full_name as patient_name, p.dob,
            dep.name as department_name, du.full_name as doctor_name,
            tr.specialty, tr.red_flag
       from visits v
       join users u on u.id = v.patient_id
       join patients p on p.user_id = v.patient_id
       left join departments dep on dep.id = v.department_id
       left join users du on du.id = v.doctor_user_id
       left join triage_results tr on tr.id = v.triage_result_id
      where v.hospital_id = $1 and ($2::text is null or v.status = $2)
      order by v.token_date desc, v.urgency asc, v.created_at asc
      limit $3`,
    [hospitalId, status, limit],
  ).then((rows) => rows.map((r) => ({ ...r, age: ageFrom(r.dob), dob: undefined }))));
});

// ------------------------------------------------------------ departments

router.get('/departments', async (req, res) => {
  const hospitalId = await staffHospitalId(req.user);
  res.json(await many(
    `select d.id, d.name, d.specialty,
            (select count(*) from doctors doc where doc.department_id = d.id)::int as doctors,
            (select count(*) from visits v
              where v.department_id = d.id and v.token_date = current_date
                and v.status in ('waiting','in_consult'))::int as waiting
       from departments d where d.hospital_id = $1 order by d.name`,
    [hospitalId]));
});

router.post('/departments', async (req, res) => {
  const hospitalId = await staffHospitalId(req.user);
  const name = str(req.body, 'name', { required: true, max: 120 });
  // The specialty string is the routing key the triage layer returns — keep it a slug.
  const specialty = str(req.body, 'specialty', { required: true, max: 64 })
    .toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '');
  if (!specialty) throw bad('specialty must contain letters or digits');

  if (await one('select 1 from departments where hospital_id = $1 and specialty = $2', [hospitalId, specialty]))
    throw bad(`a department already handles the specialty "${specialty}"`);

  const dept = await one(
    'insert into departments (hospital_id, name, specialty) values ($1,$2,$3) returning *',
    [hospitalId, name, specialty],
  );
  audit(req.user.id, 'admin.department_created', 'department', dept.id, { name, specialty });
  res.status(201).json(dept);
});

// ------------------------------------------------------------ staff

router.get('/doctors', async (req, res) => {
  const hospitalId = await staffHospitalId(req.user);
  res.json(await many(
    `select d.user_id, u.full_name, u.email, u.is_active, d.specialty, d.reg_no,
            d.is_available, d.department_id, dep.name as department_name,
            (select count(*) from visits v
              where v.doctor_user_id = d.user_id and v.token_date = current_date
                and v.status in ('waiting','in_consult'))::int as queue_today
       from doctors d
       join users u on u.id = d.user_id
       left join departments dep on dep.id = d.department_id
      where d.hospital_id = $1 order by u.full_name`,
    [hospitalId]));
});

/** Provision a doctor account. Staff never self-signup. */
router.post('/doctors', async (req, res) => {
  const hospitalId = await staffHospitalId(req.user);
  const email = emailOf(req.body);
  const fullName = str(req.body, 'full_name', { required: true, max: 120 });
  const password = str(req.body, 'password', { required: true, max: 200 });
  if (password.length < 8) throw bad('password must be at least 8 characters');
  const departmentId = req.body?.department_id ? uuid(req.body.department_id, 'department_id') : null;
  const regNo = str(req.body, 'reg_no', { max: 40 });

  if (await one('select 1 from users where email = $1', [email]))
    throw bad('an account with this email already exists');

  let specialty = str(req.body, 'specialty', { max: 64 });
  if (departmentId) {
    const dept = await one('select specialty from departments where id = $1 and hospital_id = $2', [
      departmentId, hospitalId,
    ]);
    if (!dept) throw notFound('department at your hospital');
    specialty = specialty ?? dept.specialty;
  }

  const created = await tx(async (c) => {
    const u = (
      await c.query(
        `insert into users (email, password_hash, role, full_name)
         values ($1,$2,'doctor',$3) returning id, email, role, full_name`,
        [email, await hashPassword(password), fullName],
      )
    ).rows[0];
    await c.query(
      `insert into doctors (user_id, hospital_id, department_id, specialty, reg_no)
       values ($1,$2,$3,$4,$5)`,
      [u.id, hospitalId, departmentId, specialty, regNo],
    );
    return u;
  });

  audit(req.user.id, 'admin.doctor_created', 'user', created.id, { email, departmentId });
  res.status(201).json(created);
});

router.patch('/doctors/:id', async (req, res) => {
  const hospitalId = await staffHospitalId(req.user);
  const userId = uuid(req.params.id, 'doctor id');
  const existing = await one('select * from doctors where user_id = $1 and hospital_id = $2', [
    userId, hospitalId,
  ]);
  if (!existing) throw notFound('doctor at your hospital');

  const departmentId = req.body?.department_id === undefined
    ? undefined
    : (req.body.department_id === null ? null : uuid(req.body.department_id, 'department_id'));
  if (departmentId) {
    const dept = await one('select 1 from departments where id = $1 and hospital_id = $2', [
      departmentId, hospitalId,
    ]);
    if (!dept) throw notFound('department at your hospital');
  }
  const isAvailable = req.body?.is_available === undefined ? undefined : bool(req.body, 'is_available');
  const isActive = req.body?.is_active === undefined ? undefined : bool(req.body, 'is_active');

  await tx(async (c) => {
    if (departmentId !== undefined || isAvailable !== undefined) {
      await c.query(
        `update doctors set
           department_id = case when $2 then $3::uuid else department_id end,
           is_available  = coalesce($4, is_available)
         where user_id = $1`,
        [userId, departmentId !== undefined, departmentId ?? null, isAvailable ?? null],
      );
    }
    if (isActive !== undefined) {
      await c.query('update users set is_active = $2 where id = $1', [userId, isActive]);
    }
  });

  audit(req.user.id, 'admin.doctor_updated', 'user', userId, {
    department_id: departmentId, is_available: isAvailable, is_active: isActive,
  });

  res.json(await one(
    `select d.user_id, u.full_name, u.email, u.is_active, d.specialty, d.reg_no,
            d.is_available, d.department_id, dep.name as department_name
       from doctors d join users u on u.id = d.user_id
       left join departments dep on dep.id = d.department_id
      where d.user_id = $1`,
    [userId]));
});

/** Recent trail: AI recommendations, doctor overrides, staff changes. */
router.get('/audit', async (req, res) => {
  const limit = Math.min(Number(req.query.limit) || 100, 500);
  res.json(await many(
    `select a.id, a.action, a.entity, a.entity_id, a.detail, a.created_at,
            u.full_name as actor_name, u.role as actor_role
       from audit_log a left join users u on u.id = a.actor_user_id
      order by a.id desc limit $1`,
    [limit]));
});

export default router;
