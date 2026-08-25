import { Router } from 'express';
import { one } from '../lib/db.js';
import { requireAuth, staffHospitalId } from '../lib/auth.js';
import { forbidden, notFound, uuid } from '../lib/http.js';

const router = Router();

const AI_SECRET = process.env.AI_CALLBACK_SECRET || '';

/**
 * Stream a stored file. Health records, so access is explicit:
 *  - the owner, always;
 *  - hospital staff, only for patients who have a visit at their hospital;
 *  - the AI service, with the shared secret (it fetches referenced attachments).
 */
router.get('/:id', async (req, res, next) => {
  const id = uuid(req.params.id);

  const serviceCall = AI_SECRET && req.get('x-ai-secret') === AI_SECRET;
  if (!serviceCall) {
    await new Promise((resolve, reject) =>
      requireAuth(req, res, (err) => (err ? reject(err) : resolve())),
    ).catch(next);
    if (!req.user) return;
  }

  const file = await one(
    'select id, owner_user_id, filename, mime, size_bytes, data from files where id = $1',
    [id],
  );
  if (!file) throw notFound('file');

  if (!serviceCall && file.owner_user_id !== req.user.id) {
    if (!['doctor', 'admin'].includes(req.user.role)) throw forbidden('not your file');
    const hospitalId = await staffHospitalId(req.user);
    const linked = await one(
      'select 1 from visits where patient_id = $1 and hospital_id = $2 limit 1',
      [file.owner_user_id, hospitalId],
    );
    if (!linked) throw forbidden('this patient has no visit at your hospital');
  }

  res.setHeader('content-type', file.mime);
  res.setHeader('content-length', file.size_bytes);
  res.setHeader('cache-control', 'private, max-age=3600');
  if (file.filename) {
    res.setHeader('content-disposition', `inline; filename="${file.filename.replace(/"/g, '')}"`);
  }
  res.end(file.data);
});

export default router;
