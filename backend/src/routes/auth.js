import { Router } from 'express';
import { many, one, tx } from '../lib/db.js';
import {
  googleEnabled, hashPassword, requireAuth, signToken, verifyGoogleIdToken, verifyPassword,
} from '../lib/auth.js';
import { ageFrom, bad, email as emailOf, forbidden, str, unauthorized } from '../lib/http.js';
import { audit } from '../lib/audit.js';

const router = Router();

const publicUser = (u) => ({ id: u.id, email: u.email, role: u.role, full_name: u.full_name });

/** Public: lets a client hide the Google button when the server has no client ids. */
router.get('/config', (_req, res) => res.json({ google_enabled: googleEnabled() }));

/** Patient self-signup. Doctors and admins are created by a hospital admin. */
router.post('/register', async (req, res) => {
  const email = emailOf(req.body);
  const password = str(req.body, 'password', { required: true, max: 200 });
  const fullName = str(req.body, 'full_name', { required: true, max: 120 });
  if (password.length < 8) throw bad('password must be at least 8 characters');

  if (await one('select 1 from users where email = $1', [email]))
    throw bad('an account with this email already exists');

  const user = await tx(async (c) => {
    const u = (
      await c.query(
        `insert into users (email, password_hash, role, full_name)
         values ($1, $2, 'patient', $3) returning *`,
        [email, await hashPassword(password), fullName],
      )
    ).rows[0];
    await c.query('insert into patients (user_id) values ($1)', [u.id]);
    return u;
  });

  audit(user.id, 'auth.register', 'user', user.id, { method: 'password' });
  res.status(201).json({ token: signToken(user), user: publicUser(user) });
});

router.post('/login', async (req, res) => {
  const email = emailOf(req.body);
  const password = str(req.body, 'password', { required: true, max: 200 });

  const user = await one('select * from users where email = $1', [email]);
  // Same message either way — do not leak which emails exist.
  if (!user || !(await verifyPassword(password, user.password_hash)))
    throw unauthorized('email or password is incorrect');
  if (!user.is_active) throw forbidden('this account has been deactivated');

  audit(user.id, 'auth.login', 'user', user.id, { method: 'password' });
  res.json({ token: signToken(user), user: publicUser(user) });
});

/**
 * Google sign-in. The client does the Google flow and sends the resulting ID
 * token; we verify it server-side and mint our own JWT. Patients only —
 * staff accounts are provisioned by an admin, so an unknown Google account
 * becomes a patient.
 */
router.post('/google', async (req, res) => {
  if (!googleEnabled()) throw forbidden('google sign-in is not configured on this server');
  const idToken = str(req.body, 'id_token', { required: true, max: 4096 });
  const g = await verifyGoogleIdToken(idToken);

  let user = await one('select * from users where google_sub = $1', [g.sub]);
  let created = false;

  if (!user) {
    const byEmail = await one('select * from users where email = $1', [g.email]);
    if (byEmail) {
      // Same person, first time through Google — link the accounts.
      user = await one('update users set google_sub = $2 where id = $1 returning *', [
        byEmail.id, g.sub,
      ]);
    } else {
      user = await tx(async (c) => {
        const u = (
          await c.query(
            `insert into users (email, google_sub, role, full_name)
             values ($1, $2, 'patient', $3) returning *`,
            [g.email, g.sub, g.name],
          )
        ).rows[0];
        await c.query('insert into patients (user_id) values ($1)', [u.id]);
        return u;
      });
      created = true;
    }
  }

  if (!user.is_active) throw forbidden('this account has been deactivated');
  audit(user.id, created ? 'auth.register' : 'auth.login', 'user', user.id, { method: 'google' });
  res.status(created ? 201 : 200).json({ token: signToken(user), user: publicUser(user), created });
});

/** Everything the client needs to decide which screen to open first. */
router.get('/me', requireAuth, async (req, res) => {
  const out = { user: publicUser(req.user), google_enabled: googleEnabled() };

  if (req.user.role === 'patient') {
    const p = await one('select * from patients where user_id = $1', [req.user.id]);
    const preferred = await many(
      `select h.id, h.name from patient_preferred_hospitals ph
         join hospitals h on h.id = ph.hospital_id where ph.patient_id = $1`,
      [req.user.id],
    );
    out.patient = p && {
      ...p,
      age: ageFrom(p.dob),
      app_lock_set: Boolean(p.app_lock_pin_hash),
      app_lock_pin_hash: undefined,
      preferred_hospitals: preferred,
    };
  } else if (req.user.role === 'doctor') {
    out.doctor = await one(
      `select d.*, h.name as hospital_name, dep.name as department_name
         from doctors d join hospitals h on h.id = d.hospital_id
         left join departments dep on dep.id = d.department_id
        where d.user_id = $1`,
      [req.user.id],
    );
  } else {
    out.admin = await one(
      `select a.*, h.name as hospital_name from hospital_admins a
         join hospitals h on h.id = a.hospital_id where a.user_id = $1`,
      [req.user.id],
    );
  }

  res.json(out);
});

/** App lock (appfeature.md 1.2). A local PIN on top of the session, patients only. */
router.post('/app-lock', requireAuth, async (req, res) => {
  if (req.user.role !== 'patient') throw forbidden('app lock is for patient accounts');
  const pin = str(req.body, 'pin', { required: true, max: 12 });
  if (!/^\d{4,12}$/.test(pin)) throw bad('pin must be 4 to 12 digits');
  await one('update patients set app_lock_pin_hash = $2, updated_at = now() where user_id = $1 returning user_id', [
    req.user.id, await hashPassword(pin),
  ]);
  res.json({ app_lock_set: true });
});

router.post('/app-lock/verify', requireAuth, async (req, res) => {
  const pin = str(req.body, 'pin', { required: true, max: 12 });
  const row = await one('select app_lock_pin_hash from patients where user_id = $1', [req.user.id]);
  res.json({ ok: await verifyPassword(pin, row?.app_lock_pin_hash) });
});

export default router;
