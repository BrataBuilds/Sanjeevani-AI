import { query } from './db.js';

/**
 * Append-only trail. Design_doc.md §6 requires every AI recommendation and every
 * doctor override be recoverable later. Never let a logging failure fail a request.
 */
export function audit(actorUserId, action, entity, entityId, detail) {
  return query(
    `insert into audit_log (actor_user_id, action, entity, entity_id, detail)
     values ($1, $2, $3, $4, $5)`,
    [actorUserId ?? null, action, entity ?? null, entityId ?? null, detail ? JSON.stringify(detail) : null],
  ).catch((err) => console.error('[audit] failed', action, err.message));
}
