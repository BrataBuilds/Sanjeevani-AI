import jwt from 'jsonwebtoken';
import bcrypt from 'bcryptjs';
import { OAuth2Client } from 'google-auth-library';
import { one } from './db.js';
import { forbidden, unauthorized } from './http.js';

// No fallback and no NODE_ENV condition. The old guard only fired when NODE_ENV
// was 'production', which the Dockerfile sets but `npm run dev` and `npm start`
// do not -- so a host-run instance silently signed every session with a constant
// committed to this repository. A missing signing key is fatal everywhere.
const SECRET = process.env.JWT_SECRET;
const TTL = process.env.JWT_TTL || '30d';

if (!SECRET || SECRET === 'dev-only-change-me') {
  throw new Error('JWT_SECRET must be set to a real value -- see .env.example');
}

export const hashPassword = (plain) => bcrypt.hash(plain, 10);
export const verifyPassword = (plain, hash) =>
  hash ? bcrypt.compare(plain, hash) : Promise.resolve(false);

export const signToken = (user) =>
  jwt.sign({ sub: user.id, role: user.role, email: user.email }, SECRET, { expiresIn: TTL });

/**
 * Verify a Google ID token from the Flutter app or the web app.
 * GOOGLE_CLIENT_IDS is a comma-separated allowlist of audiences; every platform
 * (android / ios / web) has its own client id and all of them must be listed.
 */
const googleClientIds = (process.env.GOOGLE_CLIENT_IDS || '')
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean);

export const googleEnabled = () => googleClientIds.length > 0;

const googleClient = new OAuth2Client();

export async function verifyGoogleIdToken(idToken) {
  if (!googleEnabled()) throw forbidden('google sign-in is not configured on this server');

  // A rejected token is the client's problem, not ours. google-auth-library
  // throws a plain Error for a forged, expired or wrong-audience token, which
  // reached the generic handler as a 500 -- so a bad sign-in looked like an
  // outage, and the library's message went out in the response.
  let ticket;
  try {
    ticket = await googleClient.verifyIdToken({ idToken, audience: googleClientIds });
  } catch (err) {
    console.warn('[auth] google id token rejected:', err.message);
    throw unauthorized('google sign-in could not be verified');
  }

  const p = ticket.getPayload();
  if (!p?.sub) throw unauthorized('google token has no subject');
  if (!p.email_verified) throw unauthorized('google account email is not verified');
  return { sub: p.sub, email: String(p.email).toLowerCase(), name: p.name || p.email, picture: p.picture };
}

/** Populates req.user from the Bearer token. */
export async function requireAuth(req, _res, next) {
  const header = req.get('authorization') || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) return next(unauthorized('missing bearer token'));
  let claims;
  try {
    claims = jwt.verify(token, SECRET);
  } catch {
    return next(unauthorized('token is invalid or expired'));
  }
  const user = await one(
    'select id, email, role, full_name, is_active from users where id = $1',
    [claims.sub],
  );
  if (!user || !user.is_active) return next(unauthorized('account is not active'));
  req.user = user;
  next();
}

/** requireRole('doctor','admin') — use after requireAuth. */
export const requireRole =
  (...roles) =>
  (req, _res, next) =>
    roles.includes(req.user?.role) ? next() : next(forbidden(`requires role: ${roles.join(' or ')}`));

/** Hospital the logged-in staff member belongs to. */
export async function staffHospitalId(user) {
  const row =
    user.role === 'doctor'
      ? await one('select hospital_id from doctors where user_id = $1', [user.id])
      : await one('select hospital_id from hospital_admins where user_id = $1', [user.id]);
  if (!row) throw forbidden('this account is not attached to a hospital');
  return row.hospital_id;
}
