const { Pool } = require('pg');

class PostgresStore {
  constructor(config) {
    this.kind = 'postgres';
    this.pool = new Pool({ connectionTimeoutMillis: 2000, ...config });
    // Si la BD se cae, las conexiones inactivas del pool emiten 'error'.
    // Sin este listener, Node lo trata como excepción no manejada y el
    // proceso entero muere. Con él, solo se registra y el pool reconecta
    // en la siguiente consulta.
    this.pool.on('error', (err) => {
      console.error(JSON.stringify({ level: 'error', msg: 'conexión a la BD perdida', error: err.message }));
    });
  }

  // Migración mínima. En un proyecto real: herramienta de migraciones (Flyway, node-pg-migrate...).
  async init() {
    await this.pool.query(`
      CREATE TABLE IF NOT EXISTS todos (
        id    SERIAL PRIMARY KEY,
        title TEXT    NOT NULL,
        done  BOOLEAN NOT NULL DEFAULT FALSE
      )`);
  }

  async ping() {
    await this.pool.query('SELECT 1');
  }

  async list() {
    const { rows } = await this.pool.query('SELECT id, title, done FROM todos ORDER BY id');
    return rows;
  }

  async create(title) {
    const { rows } = await this.pool.query(
      'INSERT INTO todos (title) VALUES ($1) RETURNING id, title, done',
      [title],
    );
    return rows[0];
  }

  async update(id, { done }) {
    const { rows } = await this.pool.query(
      'UPDATE todos SET done = $2 WHERE id = $1 RETURNING id, title, done',
      [id, done],
    );
    return rows[0] || null;
  }

  async remove(id) {
    const { rowCount } = await this.pool.query('DELETE FROM todos WHERE id = $1', [id]);
    return rowCount > 0;
  }

  async close() {
    await this.pool.end();
  }
}

module.exports = { PostgresStore };
