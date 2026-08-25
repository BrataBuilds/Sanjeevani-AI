/**
 * Inbound side of the AI seam — the endpoints the triage team calls.
 * Authenticated with a shared secret in `x-ai-secret`, not a user JWT: the
 * caller is a service, not a person.
 *
 * Contract: docs/AI-Integration-Contract.md
 */
import { Router } from 'express';
import { timingSafeEqual } from 'node:crypto';
import { many, one } from '../lib/db.js';
import { aiConfigured } from '../lib/ai.js';
import { applyTriageResult } from '../lib/triage.js';
import { forbidden, notFound, uuid } from '../lib/http.js';

const router = Router();
const SECRET = process.env.AI_CALLBACK_SECRET || '';

// This header is the only gate on every route below, so it gets the same
// treatment as JWT_SECRET in lib/auth.js. Without this the shipped default is
// live in any deployment that set JWT_SECRET and stopped there.
if (SECRET === 'dev-callback-secret' && process.env.NODE_ENV === 'production') {
  throw new Error('AI_CALLBACK_SECRET must be set to a real value in production');
}

function requireServiceSecret(req, _res, next) {
  const given = req.get('x-ai-secret') || '';
  const a = Buffer.from(given);
  const b = Buffer.from(SECRET);
  if (!SECRET || a.length !== b.length || !timingSafeEqual(a, b)) {
    return next(forbidden('invalid or missing x-ai-secret'));
  }
  next();
}

/** Unauthenticated liveness/config probe — says nothing sensitive. */
router.get('/health', (_req, res) =>
  res.json({
    triage_backend: aiConfigured() ? 'http' : 'stub',
    callback_enabled: Boolean(SECRET),
  }));

router.use(requireServiceSecret);

/**
 * Asynchronous result delivery. Idempotent: replaying the same request_id is a
 * no-op, so at-least-once delivery from the AI side is safe.
 */
router.post('/triage-callback', async (req, res) => {
  const requestId = uuid(req.body?.request_id, 'request_id');
  const existing = await one('select id, status from triage_requests where id = $1', [requestId]);
  if (!existing) throw notFound('triage request');
  if (existing.status === 'done') return res.json({ applied: false, reason: 'already applied' });
  if (req.body?.error) {
    await one(
      `update triage_requests set status = 'failed', error = $2, completed_at = now()
        where id = $1 returning id`,
      [requestId, String(req.body.error).slice(0, 500)],
    );
    return res.json({ applied: false, reason: 'recorded as failed' });
  }
  const { result } = await applyTriageResult(requestId, req.body);
  res.json({ applied: true, triage_result_id: result.id });
});

/**
 * Pull-based alternative to the outbound POST: a worker can poll this instead of
 * having the backend push. Same contract body, same callback to finish.
 */
router.get('/pending', async (req, res) => {
  const limit = Math.min(Number(req.query.limit) || 10, 100);
  const rows = await many(
    `select id, conversation_id, patient_id, request, created_at
       from triage_requests where status = 'pending'
      order by created_at limit $1`,
    [limit],
  );
  res.json(rows.map((r) => ({ request_id: r.id, created_at: r.created_at, ...r.request })));
});

/** Lets the AI team confirm what a stored request looked like. */
router.get('/requests/:id', async (req, res) => {
  const row = await one(
    `select r.*, t.id as triage_result_id from triage_requests r
       left join triage_results t on t.triage_request_id = r.id
      where r.id = $1`,
    [uuid(req.params.id)],
  );
  if (!row) throw notFound('triage request');
  res.json(row);
});

export default router;
