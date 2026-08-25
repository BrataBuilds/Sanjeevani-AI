import express from 'express';
import cors from 'cors';
import { pool } from './lib/db.js';
import { HttpError } from './lib/http.js';
import authRoutes from './routes/auth.js';
import meRoutes from './routes/me.js';
import fileRoutes from './routes/files.js';
import chatRoutes from './routes/chat.js';
import hospitalRoutes from './routes/hospitals.js';
import doctorRoutes from './routes/doctor.js';
import adminRoutes from './routes/admin.js';
import aiRoutes from './routes/ai.js';

const app = express();
app.disable('x-powered-by');
app.set('trust proxy', true);

const origins = (process.env.CORS_ORIGINS || 'http://localhost:3000')
  .split(',').map((s) => s.trim()).filter(Boolean);

app.use(cors({
  // Flutter and other native clients send no Origin header — allow those through.
  origin: (origin, cb) =>
    !origin || origins.includes('*') || origins.includes(origin)
      ? cb(null, true)
      : cb(new HttpError(403, `origin ${origin} is not allowed`)),
  credentials: false,
}));
app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ extended: false, limit: '1mb' }));

app.get('/health', async (_req, res) => {
  try {
    await pool.query('select 1');
    res.json({ ok: true, db: 'up' });
  } catch (err) {
    res.status(503).json({ ok: false, db: 'down', error: err.message });
  }
});

app.use('/auth', authRoutes);
app.use('/me', meRoutes);
app.use('/files', fileRoutes);
app.use('/conversations', chatRoutes);
app.use('/hospitals', hospitalRoutes);
app.use('/doctor', doctorRoutes);
app.use('/admin', adminRoutes);
app.use('/ai', aiRoutes);

app.use((req, res) => res.status(404).json({ error: `no route for ${req.method} ${req.path}` }));

// Express 5 forwards rejected promises from async handlers here, so routes can throw.
app.use((err, _req, res, _next) => {
  if (err instanceof HttpError) {
    return res.status(err.status).json({ error: err.message, details: err.details });
  }
  if (err?.code === 'LIMIT_FILE_SIZE') {
    return res.status(413).json({ error: 'file is too large' });
  }
  // Postgres constraint violations are user errors, not server errors.
  const pgStatus = { 23505: 409, 23503: 400, 23514: 400, '22P02': 400 }[err?.code];
  if (pgStatus) {
    return res.status(pgStatus).json({ error: err.detail || err.message });
  }
  console.error('[error]', err);
  res.status(500).json({ error: 'internal server error' });
});

const port = Number(process.env.PORT || 4000);
const server = app.listen(port, () =>
  console.log(`[api] listening on :${port}  triage=${process.env.AI_SERVICE_URL ? 'http' : 'stub'}`));

for (const sig of ['SIGTERM', 'SIGINT']) {
  process.on(sig, () => {
    server.close(() => pool.end().then(() => process.exit(0)));
  });
}

export { app };
