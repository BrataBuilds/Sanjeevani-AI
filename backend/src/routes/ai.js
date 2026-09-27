/** Public AI service status. Chat requests are made synchronously by triage.js. */
import { Router } from 'express';
import { aiConfigured } from '../lib/ai.js';

const router = Router();

router.get('/health', (_req, res) =>
  res.json({
    triage_backend: aiConfigured() ? 'http' : 'stub',
  }));

export default router;
