#!/usr/bin/env bash
# Redeploy the IIoT stack after config changes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

STACK_NAME="${STACK_NAME:-iiot}"

echo "=== Redeploying IIoT Stack ==="

SWARM_ACTIVE=$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo "inactive")

if [ "$SWARM_ACTIVE" = "active" ]; then
  echo "[*] Swarm mode — deploying stack..."
  docker stack deploy -c stack.yml --with-registry-auth "$STACK_NAME"
else
  echo "[*] Compose mode — deploying..."
  docker compose up -d --remove-orphans
fi

echo ""
echo "Stack redeployed. Check services:"
docker service ls 2>/dev/null || docker compose ps
echo ""
echo "Web UI:  http://$(hostname -I | awk '{print $1}'):8080"
echo "Grafana: http://$(hostname -I | awk '{print $1}'):3000"
