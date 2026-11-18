const express = require('express');
const { metricsMiddleware, metricsHandler } = require('./metrics');
const { requestLogger } = require('./logger');

/**
 * Crea la aplicación Express.
 * Recibe el "store" (memoria o PostgreSQL) por inyección de dependencias,
 * así las pruebas no necesitan una base de datos real.
 */
function createApp(store) {
  const app = express();
  app.use(express.json());
  app.use(requestLogger);
  app.use(metricsMiddleware);

  // Healthcheck: lo usan Docker, el load balancer y el script de despliegue.
  app.get('/health', async (req, res) => {
    const db = await store.ping().then(() => 'ok').catch(() => 'down');
    const status = db === 'ok' ? 200 : 503;
    res.status(status).json({
      status: db === 'ok' ? 'ok' : 'degraded',
      db,
      version: process.env.APP_VERSION || 'dev',
    });
  });

  app.get('/metrics', metricsHandler);

  app.get('/todos', async (req, res, next) => {
    try {
      res.json(await store.list());
    } catch (err) {
      next(err);
    }
  });

  app.post('/todos', async (req, res, next) => {
    try {
      const title = req.body?.title;
      if (typeof title !== 'string' || title.trim() === '') {
        return res.status(400).json({ error: 'title requerido' });
      }
      const todo = await store.create(title.trim());
      res.status(201).json(todo);
    } catch (err) {
      next(err);
    }
  });

  app.patch('/todos/:id', async (req, res, next) => {
    try {
      const id = Number(req.params.id);
      if (!Number.isInteger(id)) return res.status(400).json({ error: 'id inválido' });
      const todo = await store.update(id, { done: Boolean(req.body?.done) });
      if (!todo) return res.status(404).json({ error: 'no encontrado' });
      res.json(todo);
    } catch (err) {
      next(err);
    }
  });

  app.delete('/todos/:id', async (req, res, next) => {
    try {
      const id = Number(req.params.id);
      if (!Number.isInteger(id)) return res.status(400).json({ error: 'id inválido' });
      const removed = await store.remove(id);
      if (!removed) return res.status(404).json({ error: 'no encontrado' });
      res.status(204).end();
    } catch (err) {
      next(err);
    }
  });

  // Manejador de errores: log estructurado + respuesta genérica (no filtrar detalles).
  // eslint-disable-next-line no-unused-vars
  app.use((err, req, res, next) => {
    console.error(JSON.stringify({ level: 'error', msg: err.message, route: req.path }));
    res.status(500).json({ error: 'error interno' });
  });

  return app;
}

module.exports = { createApp };
