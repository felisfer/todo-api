const { createApp } = require('./app');
const { createStore } = require('./store');

const PORT = Number(process.env.PORT) || 3000;

async function main() {
  const store = await createStore();
  const app = createApp(store);

  const server = app.listen(PORT, () => {
    console.log(JSON.stringify({ level: 'info', msg: 'servidor iniciado', port: PORT, store: store.kind }));
  });

  // Apagado ordenado: Docker manda SIGTERM antes de matar el contenedor.
  const shutdown = (signal) => {
    console.log(JSON.stringify({ level: 'info', msg: 'apagando', signal }));
    server.close(async () => {
      await store.close();
      process.exit(0);
    });
  };
  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);
}

main().catch((err) => {
  console.error(JSON.stringify({ level: 'fatal', msg: err.message }));
  process.exit(1);
});
