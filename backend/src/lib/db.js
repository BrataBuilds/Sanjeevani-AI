import pg from 'pg';

export const pool = new pg.Pool({
  connectionString:
    process.env.DATABASE_URL ||
    'postgres://sanjeevani:sanjeevani@localhost:5433/sanjeevani',
  max: 10,
});

pool.on('error', (err) => console.error('[db] idle client error', err));

/** Run a parameterised query. Always use $1..$n — never string interpolation. */
export const query = (sql, params) => pool.query(sql, params);

/** First row or null. */
export async function one(sql, params) {
  const { rows } = await pool.query(sql, params);
  return rows[0] ?? null;
}

/** All rows. */
export async function many(sql, params) {
  const { rows } = await pool.query(sql, params);
  return rows;
}

/** Run fn inside a transaction; rolls back on throw. */
export async function tx(fn) {
  const client = await pool.connect();
  try {
    await client.query('begin');
    const out = await fn(client);
    await client.query('commit');
    return out;
  } catch (err) {
    await client.query('rollback').catch(() => {});
    throw err;
  } finally {
    client.release();
  }
}
