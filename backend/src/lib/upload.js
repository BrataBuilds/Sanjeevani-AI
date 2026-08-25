import multer from 'multer';
import { bad } from './http.js';
import { one } from './db.js';

const MAX_BYTES = Number(process.env.MAX_UPLOAD_BYTES || 10 * 1024 * 1024); // 10 MB

const ALLOWED = new Set([
  'image/jpeg', 'image/png', 'image/webp', 'image/heic',
  'application/pdf',
]);

/**
 * Files go straight into Postgres, so they never touch disk: memory storage,
 * hard size cap, mime allowlist. `bytea` is comfortable at this size.
 */
export const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_BYTES, files: 1 },
  fileFilter: (_req, file, cb) =>
    ALLOWED.has(file.mimetype)
      ? cb(null, true)
      : cb(bad(`unsupported file type ${file.mimetype}; allowed: ${[...ALLOWED].join(', ')}`)),
});

export async function storeFile(ownerUserId, file) {
  if (!file) throw bad('a file is required (multipart field "file")');
  return one(
    `insert into files (owner_user_id, filename, mime, size_bytes, data)
     values ($1, $2, $3, $4, $5) returning id, filename, mime, size_bytes, created_at`,
    [ownerUserId, file.originalname?.slice(0, 200) ?? null, file.mimetype, file.size, file.buffer],
  );
}
