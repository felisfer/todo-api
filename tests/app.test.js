const request = require('supertest');
const { createApp } = require('../src/app');
const { MemoryStore } = require('../src/store/memory');

let app;

beforeEach(() => {
  app = createApp(new MemoryStore());
});

describe('GET /health', () => {
  test('responde ok', async () => {
    const res = await request(app).get('/health');
    expect(res.statusCode).toBe(200);
    expect(res.body.status).toBe('ok');
  });

  test('responde 503 si la base de datos no contesta', async () => {
    const store = new MemoryStore();
    store.ping = async () => { throw new Error('sin conexión'); };
    const res = await request(createApp(store)).get('/health');
    expect(res.statusCode).toBe(503);
    expect(res.body.db).toBe('down');
  });
});

describe('/todos', () => {
  test('POST sin title regresa 400', async () => {
    const res = await request(app).post('/todos').send({});
    expect(res.statusCode).toBe(400);
  });

  test('POST crea y GET lista', async () => {
    const created = await request(app).post('/todos').send({ title: 'Preparar demo' });
    expect(created.statusCode).toBe(201);
    expect(created.body).toMatchObject({ id: 1, title: 'Preparar demo', done: false });

    const list = await request(app).get('/todos');
    expect(list.body).toHaveLength(1);
  });

  test('PATCH marca como terminada', async () => {
    await request(app).post('/todos').send({ title: 'x' });
    const res = await request(app).patch('/todos/1').send({ done: true });
    expect(res.statusCode).toBe(200);
    expect(res.body.done).toBe(true);
  });

  test('PATCH de un id inexistente regresa 404', async () => {
    const res = await request(app).patch('/todos/99').send({ done: true });
    expect(res.statusCode).toBe(404);
  });

  test('DELETE elimina', async () => {
    await request(app).post('/todos').send({ title: 'x' });
    expect((await request(app).delete('/todos/1')).statusCode).toBe(204);
    expect((await request(app).get('/todos')).body).toHaveLength(0);
  });
});

describe('GET /metrics', () => {
  test('expone métricas en formato Prometheus', async () => {
    await request(app).get('/todos');
    const res = await request(app).get('/metrics');
    expect(res.statusCode).toBe(200);
    expect(res.text).toContain('http_request_duration_seconds');
  });
});
