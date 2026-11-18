# syntax=docker/dockerfile:1

# ---- Etapa 1: dependencias de producción ----
FROM node:24-alpine AS deps
WORKDIR /app
# Copiar primero SOLO los manifiestos: esta capa se cachea mientras
# no cambien las dependencias, aunque el código cambie en cada commit.
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

# ---- Etapa 2: imagen final ----
FROM node:24-alpine
WORKDIR /app

ENV NODE_ENV=production \
    PORT=3000

# Parchear paquetes del SO y quitar herramientas que no se usan en runtime
RUN apk upgrade --no-cache \
 && rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx \
           /usr/local/lib/node_modules/corepack /usr/local/bin/corepack \
           /opt/yarn-* /usr/local/bin/yarn /usr/local/bin/yarnpkg

# Versión inyectada por el pipeline (SHA del commit) -> visible en /health
ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION}

COPY --from=deps /app/node_modules ./node_modules
COPY package.json ./
COPY src ./src

# Nunca correr como root dentro del contenedor
USER node

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1:3000/health || exit 1

CMD ["node", "src/server.js"]
