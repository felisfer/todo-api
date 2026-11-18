#!/usr/bin/env bash
# Despliega una imagen (identificada por el SHA del commit) a la EC2 de un ambiente.
# Usa AWS Systems Manager (SSM): no se abre el puerto 22 ni se guardan llaves SSH.
#
# Uso:   ./scripts/deploy.sh <staging|production> <sha>
# Rollback = ejecutar este mismo script con el SHA anterior.
#
# Requiere: AWS CLI con credenciales (en CI: OIDC o llaves del usuario IAM), jq.
set -euo pipefail

ENVIRONMENT="${1:?Uso: deploy.sh <staging|production> <sha>}"
SHA="${2:?Falta el SHA del commit}"
REPO="${GITHUB_REPOSITORY:-felisfer/todo-api}"
IMAGE="ghcr.io/${REPO,,}:${SHA}"      # GHCR exige minúsculas

echo "==> Desplegando ${IMAGE} en '${ENVIRONMENT}'"

INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:App,Values=todo-api" \
            "Name=tag:Environment,Values=${ENVIRONMENT}" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)

if [[ -z "$INSTANCE_ID" || "$INSTANCE_ID" == "None" ]]; then
  echo "ERROR: no hay instancia en ejecución para el ambiente '${ENVIRONMENT}'" >&2
  exit 1
fi
echo "==> Instancia: ${INSTANCE_ID}"

# Comandos que se ejecutan DENTRO de la EC2.
# Si la nueva versión no pasa el healthcheck, se restaura la anterior.
read -r -d '' REMOTE_SCRIPT <<EOF || true
set -e
PREV=\$(docker inspect --format '{{.Config.Image}}' todo-api 2>/dev/null || echo "")
docker pull ${IMAGE}
docker rm -f todo-api >/dev/null 2>&1 || true
docker run -d --name todo-api --restart unless-stopped -p 80:3000 ${IMAGE}
for i in \$(seq 1 20); do
  if curl -fsS http://127.0.0.1/health >/dev/null; then echo "healthcheck OK"; exit 0; fi
  sleep 3
done
echo "healthcheck FALLÓ, restaurando \$PREV"
docker rm -f todo-api || true
if [ -n "\$PREV" ]; then docker run -d --name todo-api --restart unless-stopped -p 80:3000 "\$PREV"; fi
exit 1
EOF

PARAMS=$(jq -n --arg s "$REMOTE_SCRIPT" '{commands: [$s]}')

COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --comment "deploy ${SHA:0:7} -> ${ENVIRONMENT}" \
  --parameters "$PARAMS" \
  --query 'Command.CommandId' --output text)

echo "==> Comando SSM: ${COMMAND_ID}. Esperando resultado..."
aws ssm wait command-executed --command-id "$COMMAND_ID" --instance-id "$INSTANCE_ID" || true

RESULT=$(aws ssm get-command-invocation --command-id "$COMMAND_ID" --instance-id "$INSTANCE_ID")
echo "$RESULT" | jq -r '.StandardOutputContent'
STATUS=$(echo "$RESULT" | jq -r '.Status')

PUBLIC_DNS=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicDnsName' --output text)
URL="http://${PUBLIC_DNS}"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "url=${URL}" >> "$GITHUB_OUTPUT"
fi

if [[ "$STATUS" != "Success" ]]; then
  echo "$RESULT" | jq -r '.StandardErrorContent' >&2
  echo "ERROR: el despliegue terminó con estado ${STATUS}" >&2
  exit 1
fi

echo "==> Listo: ${URL}/health"
