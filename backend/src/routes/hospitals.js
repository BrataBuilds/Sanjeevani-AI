import { Router } from 'express';
import { many, one } from '../lib/db.js';
import { requireAuth } from '../lib/auth.js';
import { notFound, num, uuid } from '../lib/http.js';
import { distanceKm } from '../lib/triage.js';

const router = Router();
router.use(requireAuth);

/** ?lat=&lng= sorts by distance; otherwise alphabetical. */
router.get('/', async (req, res) => {
  const lat = num(req.query, 'lat', { min: -90, max: 90 });
  const lng = num(req.query, 'lng', { min: -180, max: 180 });

  const rows = await many(
    `select h.id, h.name, h.address, h.city, h.phone, h.lat, h.lng,
            coalesce(array_agg(distinct d.specialty) filter (where d.specialty is not null), '{}') as specialties,
            (select count(*) from visits v
              where v.hospital_id = h.id and v.token_date = current_date
                and v.status in ('waiting','in_consult'))::int as queue_length
       from hospitals h left join departments d on d.hospital_id = h.id
      group by h.id order by h.name`,
  );

  const withDistance = lat !== null && lng !== null
    ? rows
        .map((h) => ({ ...h, distance_km: distanceKm({ lat, lng }, h) }))
        .sort((a, b) => (a.distance_km ?? 1e9) - (b.distance_km ?? 1e9))
    : rows;

  res.json(withDistance);
});

router.get('/:id', async (req, res) => {
  const id = uuid(req.params.id);
  const hospital = await one('select * from hospitals where id = $1', [id]);
  if (!hospital) throw notFound('hospital');
  const departments = await many(
    `select d.id, d.name, d.specialty,
            (select count(*) from doctors doc
              where doc.department_id = d.id and doc.is_available)::int as available_doctors
       from departments d where d.hospital_id = $1 order by d.name`,
    [id],
  );
  res.json({ ...hospital, departments });
});

export default router;
