# todo-api

API de tareas (Node.js + Express) que sirve de **hilo conductor** para la presentación
*"DevOps en la práctica: del `git push` a producción"*. La app es deliberadamente simple;
lo interesante es todo lo que la rodea.

> **¿Quieres reproducir la práctica en tu cuenta?** Sigue
> **[docs/INFRA.md](docs/INFRA.md)**: 7 pasos, de hacer fork a tener tu pipeline
> desplegando en AWS (≈ 1 hora, gratis con el plan *Free* de AWS).

```
 git push ─► CI (lint, tests, build, Trivy) ─► GHCR ─► CD ─► EC2 staging ─► (aprobación) ─► EC2 production
                                                                                         │
                                                         Prometheus + Grafana ◄──────────┘
```

## Qué hay en el repositorio

| Ruta | Qué demuestra |
|------|---------------|---------------------|
| `src/`, `tests/` | App con healthcheck, métricas y logs estructurados; pruebas con Jest |
| `.github/workflows/ci.yml` | CI: matriz de Node, lint, pruebas, build de imagen, escaneo, push a GHCR |
| `.github/workflows/cd.yml` | CD: staging automático, producción con aprobación, rollback manual |
| `.github/workflows/terraform.yml` | `fmt` + `validate` de la infraestructura en cada PR |
| `.github/CODEOWNERS`, `pull_request_template.md`, `dependabot.yml` | Flujo de PRs y actualizaciones automáticas |
| `Dockerfile` / `Dockerfile.antes` | Imagen multi-stage, no-root, con healthcheck vs. versión "de tarea" |
| `docker-compose*.yml` | Base (parecida a prod) + override de desarrollo + monitoreo |
| `infra/bootstrap/` | Bucket de estado, identidad de GitHub Actions (OIDC o usuario IAM) con mínimo privilegio |
| `infra/app/` | EC2 por ambiente, sin puerto 22 (administración por SSM) |
| `scripts/deploy.sh` | Despliegue por SHA con healthcheck y auto-rollback |
| `monitoring/` | Prometheus, alertas por síntomas y dashboard de Golden Signals |
| `docs/INFRA.md` | **Práctica paso a paso** para montar todo en tu propia cuenta |

## Endpoints

| Método | Ruta | Descripción |
|--------|------|-------------|
| GET | `/health` | Estado de la app y de la BD (503 si la BD no responde) |
| GET | `/metrics` | Métricas en formato Prometheus |
| GET | `/todos` | Lista de tareas |
| POST | `/todos` | Crea `{ "title": "..." }` |
| PATCH | `/todos/:id` | Actualiza `{ "done": true }` |
| DELETE | `/todos/:id` | Elimina |

Almacenamiento: si existe `DB_HOST` usa PostgreSQL; si no, memoria (pruebas y EC2 de la demo).

## Uso local

Requisitos: Node 22+ y Docker.

```bash
# 1. Sin Docker
npm ci
npm test
npm run dev                       # http://localhost:3000

# 2. Con Docker Compose (app + PostgreSQL, recarga al guardar)
mkdir -p secrets && printf "cambia-esto" > secrets/db_password.txt   # bash / Git Bash
docker compose up --build
curl -X POST localhost:3000/todos -H 'Content-Type: application/json' -d '{"title":"hola"}'

# 3. Con observabilidad (Prometheus :9090, Grafana :3001)
docker compose -f docker-compose.yml -f docker-compose.override.yml \
               -f docker-compose.monitoring.yml up -d --build
# Grafana > Dashboards > DevOps demo > "todo-api — Golden Signals"

# 4. Comparar tamaños de imagen (bloque 4)
docker build -f Dockerfile.antes -t todo-api:antes .
docker build -t todo-api:despues .
docker images todo-api
```

En **PowerShell** no uses `echo ... >`: en Windows PowerShell 5.1 guarda el archivo en
UTF-16 y PostgreSQL falla con `invalid byte sequence for encoding "UTF8": 0xff`. Usa:

```powershell
New-Item -ItemType Directory -Force secrets | Out-Null
[IO.File]::WriteAllText("$PWD\secrets\db_password.txt", "cambia-esto")   # UTF-8 sin BOM ni salto de línea
```

## Desplegar en AWS

La guía completa está en **[docs/INFRA.md](docs/INFRA.md)**. En resumen:

| Paso | Qué haces | Dónde |
|---|---|---|
| 1 | Fork, activar Actions, cambiar el usuario por el tuyo | GitHub / VS Code |
| 2 | Esperar a que CI publique la imagen y hacerla pública | GitHub → Packages |
| 3 | `terraform apply` en `infra/bootstrap` y crear la llave del usuario de despliegue | Terminal |
| 4 | Ambientes `staging` y `production` con los secretos de la llave | GitHub → Environments |
| 5 | `terraform apply` en `infra/app` para cada ambiente | Terminal |
| 6 | PR → merge → staging automático → aprobar → producción | GitHub → Actions |
| 7 | `terraform destroy` y borrar la llave | Terminal |

**Rollback:** Actions → CD → *Run workflow* → ambiente + SHA anterior.

> ⚠️ Al terminar: paso 7 de la guía. Los servidores son lo único que consume horas del plan gratuito.

## Convenciones

- Commits: [Conventional Commits](https://www.conventionalcommits.org/es/) (`feat:`, `fix:`, `docs:`, `chore:`…).
- Ramas cortas desde `main` (trunk-based); todo cambio entra por PR con CI en verde.
