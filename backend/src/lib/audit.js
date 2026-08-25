import { query } from './db.js';

/**
 * Append-only trail. Design_doc.md §6 requires every AI recommendation and every
 * doctor override be recoverable later. Never let a logging failure fail a request.
 *
 * `hospitalId` is what `GET /admin/audit` scopes on, so pass it whenever the event
 * belongs to one hospital. Leave it null for events that belong to no hospital --
 * a patient registering, logging in, or editing their own profile. Those rows stay
 * invisible to every hospital admin, which is the intent: an admin's trail is their
 * own hospital's activity, not the platform's.
 */
export function audit(actorUserId, action, entity, entityId, detail, hospitalId) {
  return query(
    `insert into audit_log (actor_user_id, hospital_id, action, entity, entity_id, detail)
     values ($1, $2, $3, $4, $5, $6)`,
    [
      actorUserId ?? null, hospitalId ?? null, action, entity ?? null, entityId ?? null,
      detail ? JSON.stringify(detail) : null,
    ],
  ).catch((err) => console.error('[audit] failed', action, err.message));
}
