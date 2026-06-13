#!/usr/bin/env bash
# Industrial IoT Observability Stack — One-Command Setup
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Sandun-S/industrial-iot-observability-stack-deploy/main/scripts/setup.sh | bash
#   OR
#   ./setup.sh
#
# This script:
#   1. Checks prerequisites (Docker)
#   2. Initializes Docker Swarm (if not already active)
#   3. Detects architecture (amd64 or arm64)
#   4. Creates required directories
#   5. Sets up Grafana provisioning
#   6. Pulls Docker images
#   7. Deploys the stack

set -euo pipefail

# ── Configuration ───────────────────────────────────────────────────────────
REGISTRY="${REGISTRY:-ghcr.io/sandun-s/industrial-iot-observability-stack}"
STACK_NAME="${STACK_NAME:-iiot}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

banner() {
  echo -e "${BLUE}"
  echo "╔══════════════════════════════════════════════════════════╗"
  echo "║   Industrial IoT Observability Stack — Setup            ║"
  echo "║   MQTT → InfluxDB → Grafana | Open Source Observability ║"
  echo "╚══════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
}

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
step()  { echo -e "\n${BLUE}[$1]${NC} $2"; }

# ── Main ────────────────────────────────────────────────────────────────────
banner

# 1. Check prerequisites
step "1/7" "Checking prerequisites..."

if ! command -v docker &>/dev/null; then
  warn "Docker not found. Installing Docker..."
  curl -fsSL https://get.docker.com | bash
  if command -v usermod &>/dev/null; then
    sudo usermod -aG docker "$USER" 2>/dev/null || true
  fi
  info "Docker installed. You may need to log out and back in for group changes."
else
  info "Docker found: $(docker --version)"
fi

# 2. Initialize Swarm (or check status)
step "2/7" "Initializing Docker Swarm..."

SWARM_STATE=$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo "inactive")

if [ "$SWARM_STATE" = "active" ]; then
  info "Docker Swarm is active."
elif [ "$SWARM_STATE" = "inactive" ]; then
  warn "Docker Swarm not active. Initializing..."
  docker swarm init 2>/dev/null || {
    warn "Could not init Swarm. If you're on a single node, try: docker swarm init"
    warn "Falling back to Docker Compose mode..."
    COMPOSE_MODE=true
  }
  info "Docker Swarm initialized."
else
  warn "Docker Swarm state: $SWARM_STATE. Falling back to Compose mode."
  COMPOSE_MODE=true
fi

# 3. Detect architecture
step "3/7" "Detecting system architecture..."

ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64)   ARCH_TAG="amd64.latest" ;;
  aarch64|arm64)  ARCH_TAG="arm64.latest" ;;
  armv7l)         ARCH_TAG="arm.latest" ;;
  *)              warn "Unknown architecture: $ARCH. Using amd64.latest as fallback."
                  ARCH_TAG="amd64.latest" ;;
esac
info "Architecture: $ARCH → tag: $ARCH_TAG"

# 4. Create directories
step "4/7" "Creating directories..."

cd "$PROJECT_DIR"
mkdir -p config grafana/provisioning/{datasources,dashboards} examples
info "Directories created."

# 5. Setup Grafana provisioning
step "5/7" "Setting up Grafana provisioning..."

# InfluxDB datasource
cat > grafana/provisioning/datasources/influxdb.yaml << 'GRAFEOF'
apiVersion: 1
datasources:
  - name: InfluxDB
    type: influxdb
    access: proxy
    url: http://influxdb:8086
    database: iiot
    isDefault: true
    jsonData:
      httpMode: GET
    editable: true
GRAFEOF

# Dashboard provider
cat > grafana/provisioning/dashboards/dashboard-provider.yaml << 'GRAFEOF2'
apiVersion: 1
providers:
  - name: IIoT
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /etc/grafana/provisioning/dashboards
GRAFEOF2

# Grafana config
cat > grafana/grafana.ini << 'GRAFEOF3'
[server]
http_port = 3000
domain = localhost
[security]
admin_user = admin
admin_password = admin
allow_embedding = true
[auth.anonymous]
enabled = true
org_role = Viewer
GRAFEOF3

info "Grafana provisioning configured."

# 6. Pull images
step "6/7" "Pulling Docker images..."

# Update image references for architecture
if [ -f stack.yml ]; then
  sed -i "s|:latest|:${ARCH_TAG}|g" stack.yml
fi

echo "Pulling infrastructure images..."
docker pull influxdb:1.8 &
docker pull eclipse-mosquitto:2 &
docker pull grafana/grafana:latest &
wait
info "Infrastructure images pulled."

echo "Pulling IIoT images..."
docker pull "${REGISTRY}/mqtt-reader:${ARCH_TAG}" 2>/dev/null || {
  warn "Could not pull mqtt-reader:${ARCH_TAG}. Image may not exist yet."
  warn "Build it from source: https://github.com/Sandun-S/industrial-iot-observability-stack"
}
docker pull "${REGISTRY}/web-ui:${ARCH_TAG}" 2>/dev/null || {
  warn "Could not pull web-ui:${ARCH_TAG}. Image may not exist yet."
}
info "IIoT images pulled (or warnings above if not yet published)."

# 7. Deploy stack
step "7/7" "Deploying the stack..."

if [ "${COMPOSE_MODE:-false}" = "true" ] || [ "$SWARM_STATE" != "active" ]; then
  warn "Using Docker Compose mode (no Swarm detected)."
  if [ -f docker-compose.yml ]; then
    docker compose up -d --remove-orphans
    info "Stack deployed via Docker Compose."
  else
    error "docker-compose.yml not found in $PROJECT_DIR"
  fi
else
  docker stack deploy -c stack.yml --with-registry-auth "$STACK_NAME"
  info "Stack deployed via Docker Swarm."
fi

# ── Done ─────────────────────────────────────────────────────────────────────
# Get host IP
HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         Setup Complete!                                  ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  📡 Web UI:    http://${HOST_IP}:8080"
echo "  📈 Grafana:   http://${HOST_IP}:3000  (admin / admin)"
echo "  💾 InfluxDB:  http://${HOST_IP}:8086  (database: iiot)"
echo "  📨 MQTT:      ${HOST_IP}:1883"
echo ""
echo "  Next steps:"
echo "  1. Open Web UI: http://${HOST_IP}:8080"
echo "  2. Add MQTT reader configurations"
echo "  3. Publish test data:"
echo "     mosquitto_pub -h ${HOST_IP} -t 'iiot/test' -m '{\"value\": 23.5}'"
echo "  4. View in Grafana: http://${HOST_IP}:3000"
echo ""
echo "  Useful commands:"
echo "    ./scripts/deploy.sh        # Redeploy after config changes"
echo "    ./scripts/add-reader.sh    # Add a new MQTT reader"
echo "    docker service ls          # List running services"
echo ""
echo -e "${YELLOW}  ⚠ If this is a Raspberry Pi, make sure Docker is installed:${NC}"
echo -e "${YELLOW}     curl -fsSL https://get.docker.com | bash${NC}"
echo ""
