/**
 * Firebase Authentication ID tokens.
 *
 * The app signs the patient in with Firebase (Google, phone, email — whichever
 * providers are enabled there) and sends the resulting ID token. We verify it and
 * mint our own JWT. Nothing Firebase-issued is trusted past that point, and roles
 * come from our users table, never from the token.
 *
 * No service-account key and no firebase-admin dependency: a Firebase ID token is
 * an ordinary RS256 JWT signed by a well-known Google key, so verifying it needs
 * the project id and Google's public certificates and nothing else. A service
 * account only buys Admin operations (custom claims, user management) that this
 * repo has no use for — so it is one fewer private key to store, mount and leak.
 *
 * Spec: https://firebase.google.com/docs/auth/admin/verify-id-tokens#verify_id_tokens_using_a_third-party_jwt_library
 */
import jwt from 'jsonwebtoken';
import { unauthorized } from './http.js';

const CERT_URL =
  'https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com';

const projectId = (process.env.FIREBASE_PROJECT_ID || '').trim();

export const firebaseEnabled = () => projectId.length > 0;

// Google rotates these keys and tells us how long they are good for. Refetching
// per sign-in would put a network round trip on the login path and get us rate
// limited; honouring max-age is what the documented flow asks for.
let cache = { certs: null, expiresAt: 0 };

async function certificates() {
  if (cache.certs && Date.now() < cache.expiresAt) return cache.certs;

  const res = await fetch(CERT_URL, { signal: AbortSignal.timeout(10_000) });
  if (!res.ok) throw new Error(`could not fetch Google signing certificates (${res.status})`);

  const certs = await res.json();
  const maxAge = /max-age=(\d+)/.exec(res.headers.get('cache-control') || '')?.[1];
  cache = {
    certs,
    // A short floor so a missing/odd header cannot make us refetch every request.
    expiresAt: Date.now() + Math.max(Number(maxAge) || 0, 300) * 1000,
  };
  return certs;
}

/**
 * @returns {Promise<{uid:string, email:string|null, emailVerified:boolean, name:string|null, picture:string|null, signInProvider:string|null}>}
 */
export async function verifyFirebaseIdToken(idToken) {
  if (!firebaseEnabled()) {
    throw unauthorized('firebase sign-in is not configured on this server');
  }

  const decoded = jwt.decode(idToken, { complete: true });
  const kid = decoded?.header?.kid;
  if (!kid || decoded?.header?.alg !== 'RS256') {
    throw unauthorized('firebase token is not a signed ID token');
  }

  const certs = await certificates();
  const cert = certs[kid];
  // An unknown kid is usually a token signed by a key we have not fetched since a
  // rotation, so drop the cache and look once more before rejecting.
  if (!cert) {
    cache = { certs: null, expiresAt: 0 };
    const fresh = await certificates();
    if (!fresh[kid]) throw unauthorized('firebase token was signed by an unknown key');
  }

  let claims;
  try {
    claims = jwt.verify(idToken, (cache.certs || certs)[kid], {
      algorithms: ['RS256'],
      audience: projectId,
      issuer: `https://securetoken.google.com/${projectId}`,
    });
  } catch (err) {
    // Forged, expired, or issued for somebody else's Firebase project. All of
    // those are the caller's problem, so none of them are a 500.
    console.warn('[auth] firebase id token rejected:', err.message);
    throw unauthorized('firebase sign-in could not be verified');
  }

  // `sub` is the Firebase uid and the only stable identifier here: a user can
  // change their email, and on some providers there is no email at all.
  if (!claims.sub) throw unauthorized('firebase token has no subject');
  if (claims.auth_time && claims.auth_time * 1000 > Date.now() + 60_000) {
    throw unauthorized('firebase token was issued in the future');
  }

  return {
    uid: claims.sub,
    email: claims.email ? String(claims.email).toLowerCase() : null,
    emailVerified: claims.email_verified === true,
    name: claims.name || claims.email || null,
    picture: claims.picture || null,
    signInProvider: claims.firebase?.sign_in_provider ?? null,
  };
}
