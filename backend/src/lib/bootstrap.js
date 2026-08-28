/**
 * The one account the system cannot provision for itself.
 *
 * Every doctor is created by a hospital admin, and every admin is created by
 * another admin — which leaves no way to get the first one. The demo seed used to
 * paper over that with a hardcoded admin sharing a password published in this
 * repository. Instead the first admin comes from the environment, so a real
 * deployment sets its own credentials and no account exists that we shipped.
 *
 * Runs on every boot and is idempotent: the environment is the source of truth
 * for this account, so rotating ADMIN_PASSWORD and restarting is how you change
 * it. Leave ADMIN_EMAIL and ADMIN_PASSWORD unset to skip entirely.
 */
import { one, tx } from './db.js';
import { hashPassword } from './auth.js';

const MIN_PASSWORD = 12;

export async function bootstrapAdmin() {
  const email = (process.env.ADMIN_EMAIL || '').trim().toLowerCase();
  const password = process.env.ADMIN_PASSWORD || '';
  const hospitalName = (process.env.ADMIN_HOSPITAL || '').trim();

  if (!email && !password && !hospitalName) return null;

  // Half-configured is a deployment mistake worth failing loudly on, not
  // something to guess our way through.
  if (!email || !password || !hospitalName) {
    throw new Error(
      'ADMIN_EMAIL, ADMIN_PASSWORD and ADMIN_HOSPITAL must be set together -- see .env.example',
    );
  }
  if (password.length < MIN_PASSWORD) {
    throw new Error(`ADMIN_PASSWORD must be at least ${MIN_PASSWORD} characters`);
  }

  const existing = await one('select id, role from users where email = $1', [email]);
  if (existing && existing.role !== 'admin') {
    // Silently promoting a patient to hospital admin because someone reused an
    // address in .env is not a mistake worth making automatically.
    throw new Error(
      `ADMIN_EMAIL ${email} already belongs to a ${existing.role} account; use a different address`,
    );
  }

  const passwordHash = await hashPassword(password);

  return tx(async (c) => {
    const hospital =
      (await c.query('select id, name from hospitals where name = $1', [hospitalName])).rows[0] ??
      (await c.query('insert into hospitals (name) values ($1) returning id, name', [hospitalName]))
        .rows[0];

    const user = (
      await c.query(
        `insert into users (email, password_hash, role, full_name, is_active)
         values ($1, $2, 'admin', $3, true)
         on conflict (email) do update
            set password_hash = excluded.password_hash,
                full_name     = excluded.full_name,
                is_active     = true
         returning id, email, full_name`,
        [email, passwordHash, process.env.ADMIN_NAME?.trim() || 'Hospital administrator'],
      )
    ).rows[0];

    await c.query(
      `insert into hospital_admins (user_id, hospital_id) values ($1, $2)
       on conflict (user_id) do update set hospital_id = excluded.hospital_id`,
      [user.id, hospital.id],
    );

    return { email: user.email, hospital: hospital.name, created: !existing };
  });
}
