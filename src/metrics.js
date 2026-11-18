const client = require('prom-client');

const register = new client.Registry();
client.collectDefaultMetrics({ register }); // CPU, memoria, event loop de Node

// Histograma de latencia: de aquí salen latencia (p95), tráfico y tasa de errores.
const httpDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duración de peticiones HTTP',
  labelNames: ['method', 'route', 'status'],
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5],
  registers: [register],
});

function metricsMiddleware(req, res, next) {
  if (req.path === '/metrics') return next();
  const end = httpDuration.startTimer();
  res.on('finish', () => {
    // Usar la ruta "plantilla" (/todos/:id) y no la real (/todos/42)
    // para no crear una serie por cada id (explosión de cardinalidad).
    const route = req.route ? req.baseUrl + req.route.path : 'unmatched';
    end({ method: req.method, route, status: res.statusCode });
  });
  next();
}

async function metricsHandler(req, res) {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
}

module.exports = { metricsMiddleware, metricsHandler, register };
