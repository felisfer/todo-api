// Logs estructurados (una línea JSON por petición): fáciles de filtrar en
// CloudWatch, Loki, etc. Ej: {"level":"info","method":"GET","route":"/todos","status":200,"ms":3}
function requestLogger(req, res, next) {
  if (process.env.NODE_ENV === 'test' || req.path === '/metrics') return next();
  const start = process.hrtime.bigint();
  res.on('finish', () => {
    const ms = Number(process.hrtime.bigint() - start) / 1e6;
    console.log(JSON.stringify({
      level: res.statusCode >= 500 ? 'error' : 'info',
      method: req.method,
      route: req.originalUrl,
      status: res.statusCode,
      ms: Math.round(ms),
    }));
  });
  next();
}

module.exports = { requestLogger };
