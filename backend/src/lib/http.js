/** Thrown anywhere in a route; turned into a JSON response by the error handler. */
export class HttpError extends Error {
  constructor(status, message, details) {
    super(message);
    this.status = status;
    this.details = details;
  }
}

export const bad = (msg, details) => new HttpError(400, msg, details);
export const unauthorized = (msg = 'not authenticated') => new HttpError(401, msg);
export const forbidden = (msg = 'not allowed') => new HttpError(403, msg);
export const notFound = (msg = 'not found') => new HttpError(404, msg);

/** Trim a string field; throws if required and empty. Caps length. */
export function str(body, field, { required = false, max = 500 } = {}) {
  const raw = body?.[field];
  if (raw === undefined || raw === null || raw === '') {
    if (required) throw bad(`${field} is required`);
    return null;
  }
  if (typeof raw !== 'string') throw bad(`${field} must be a string`);
  const v = raw.trim();
  if (required && !v) throw bad(`${field} is required`);
  if (v.length > max) throw bad(`${field} must be at most ${max} characters`);
  return v || null;
}

export function num(body, field, { required = false, min, max } = {}) {
  const raw = body?.[field];
  if (raw === undefined || raw === null || raw === '') {
    if (required) throw bad(`${field} is required`);
    return null;
  }
  const v = Number(raw);
  if (!Number.isFinite(v)) throw bad(`${field} must be a number`);
  if (min !== undefined && v < min) throw bad(`${field} must be >= ${min}`);
  if (max !== undefined && v > max) throw bad(`${field} must be <= ${max}`);
  return v;
}

export function bool(body, field, fallback = null) {
  const raw = body?.[field];
  if (raw === undefined || raw === null || raw === '') return fallback;
  return raw === true || raw === 'true' || raw === 1 || raw === '1';
}

/** One of a fixed set, matching the CHECK constraints in the schema. */
export function enumOf(body, field, allowed, { required = false } = {}) {
  const v = str(body, field, { required, max: 64 });
  if (v === null) return null;
  if (!allowed.includes(v)) throw bad(`${field} must be one of: ${allowed.join(', ')}`);
  return v;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function uuid(value, label = 'id') {
  if (typeof value !== 'string' || !UUID.test(value)) throw bad(`${label} must be a uuid`);
  return value;
}

export function email(body, field = 'email') {
  const v = str(body, field, { required: true, max: 254 }).toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v)) throw bad('email is not valid');
  return v;
}

/** Whole years between dob and today. Age is derived, never stored. */
export function ageFrom(dob) {
  if (!dob) return null;
  const d = new Date(dob);
  if (Number.isNaN(d.getTime())) return null;
  const now = new Date();
  let age = now.getUTCFullYear() - d.getUTCFullYear();
  const m = now.getUTCMonth() - d.getUTCMonth();
  if (m < 0 || (m === 0 && now.getUTCDate() < d.getUTCDate())) age -= 1;
  return age >= 0 ? age : null;
}
