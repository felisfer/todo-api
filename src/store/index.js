const fs = require('node:fs');
const { MemoryStore } = require('./memory');

/**
 * Elige el almacenamiento según la configuración (12-factor: config por entorno).
 *   - Sin DB_HOST  -> memoria (desarrollo rápido, pruebas, demo en EC2)
 *   - Con DB_HOST  -> PostgreSQL
 * La contraseña se lee de un archivo (Docker secrets) o de DB_PASSWORD.
 */
async function createStore(env = process.env) {
  if (!env.DB_HOST) return new MemoryStore();

  const { PostgresStore } = require('./postgres');
  const password = env.DB_PASSWORD_FILE
    ? fs.readFileSync(env.DB_PASSWORD_FILE, 'utf8').trim()
    : env.DB_PASSWORD;

  const store = new PostgresStore({
    host: env.DB_HOST,
    port: Number(env.DB_PORT) || 5432,
    user: env.DB_USER || 'postgres',
    database: env.DB_NAME || 'todos',
    password,
  });
  await store.init();
  return store;
}

module.exports = { createStore };
