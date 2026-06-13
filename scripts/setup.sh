#!/usr/bin/env bash
# Industrial IoT Observability Stack — One-Command Setup
#
# Designed for fresh OS install. Handles everything automatically:
#   - Installs Docker if missing
#   - Initializes Docker Swarm (or uses Compose on single host)
#   - Detects architecture (amd64/arm64)
#   - Pulls images and deploys the full stack
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Sandun-S/industrial-iot-observability-stack-deploy/main/scripts/setup.sh | bash
#   OR
#   ./setup.sh

set -euo pipefail

REGISTRY="${REGISTRY:-ghcr.io/sandun-s/industrial-iot-observability-stack}"
STACK_NAME="${STACK_NAME:-iiot}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

banner() {
  echo -e "${BLUE}"
  echo "╔══════════════════════════════════════════════════════════╗"
  echo "║   Industrial IoT Observability Stack — Setup            ║"
  echo "║   MQTT → InfluxDB → Grafana | Open Source Observability ║"
  echo "╚══════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
}
info()  { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[--]${NC} $1"; }
fail()  { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }
step()  { echo -e "\n${BLUE}[$1]${NC} $2"; }

banner

# ── Step 1: Check/install Docker ─────────────────────────────────────────
step "1/6" "Checking Docker..."

NEED_RELOGIN=false

if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
  info "Docker is installed and running: $(docker --version)"
else
  if ! command -v docker &>/dev/null; then
    warn "Docker not found. Installing..."
    curl -fsSL https://get.docker.com | sh || fail "Docker install failed"
    info "Docker installed."
    NEED_RELOGIN=true
  fi

  # Docker installed but daemon might not be running or user not in docker group
  if ! docker info &>/dev/null 2>&1; then
    if id -nG "$USER" | grep -qw docker; then
      # User is in docker group but daemon might not be running
      if command -v systemctl &>/dev/null; then
        sudo systemctl start docker 2>/dev/null || true
        sudo systemctl enable docker 2>/dev/null || true
      fi
    else
      warn "Adding $USER to docker group..."
      sudo usermod -aG docker "$USER" 2>/dev/null || true
      NEED_RELOGIN=true
    fi
  fi
fi

if [ "$NEED_RELOGIN" = true ]; then
  warn "Docker was just installed/configured. Re-login may be needed."
  warn "Attempting to use Docker with sg/sudo for this session..."
  # Try to proceed — user may need to log out/in but let's try
fi

# ── Step 2: Detect OS and architecture ───────────────────────────────────
step "2/6" "Detecting system..."

ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64)   ARCH_TAG="amd64.latest" ;;
  aarch64|arm64)  ARCH_TAG="arm64.latest" ;;
  armv7l)         ARCH_TAG="arm.latest" ;;
  *)              warn "Unknown arch: $ARCH. Using amd64."; ARCH_TAG="amd64.latest" ;;
esac

# Check if this is Raspberry Pi
if [ -f /proc/device-tree/model ]; then
  PI_MODEL=$(tr -d '\0' < /proc/device-tree/model 2>/dev/null || echo "Unknown")
  info "Raspberry Pi detected: $PI_MODEL"
fi
info "Architecture: $ARCH → image tag: $ARCH_TAG"

# ── Step 3: Initialize Docker Swarm ──────────────────────────────────────
step "3/6" "Setting up Docker Swarm..."

SWARM_STATE=$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo "inactive")
COMPOSE_MODE=false

if [ "$SWARM_STATE" = "active" ]; then
  info "Docker Swarm is active — using stack deploy."
elif [ "$SWARM_STATE" = "inactive" ]; then
  warn "Docker Swarm not active. Trying to init..."
  if docker swarm init 2>/dev/null; then
    info "Docker Swarm initialized."
  else
    warn "Could not init Swarm (single NIC? firewalled?). Using Compose mode."
    COMPOSE_MODE=true
  fi
else
  warn "Swarm state: $SWARM_STATE. Using Compose mode."
  COMPOSE_MODE=true
fi

# ── Step 4: Setup directories and configs ────────────────────────────────
step "4/6" "Setting up configuration..."

cd "$PROJECT_DIR"
mkdir -p config grafana/provisioning/{datasources,dashboards}

# Skip overwriting existing configs
if [ ! -f grafana/provisioning/datasources/influxdb.yaml ]; then
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
fi

if [ ! -f grafana/provisioning/dashboards/dashboard-provider.yaml ]; then
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
fi

if [ ! -f grafana/grafana.ini ]; then
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
fi

# Create example reader config if none exist
if [ ! -f config/mqtt-reader-example.yaml ] && [ ! "$(ls -A config/*.yaml 2>/dev/null)" ]; then
  cat > config/mqtt-reader-example.yaml << 'CONFEOF'
reader:
  name: "example-reader"
  description: "Default reader — edit via Web UI"
mqtt:
  broker: "tcp://mosquitto:1883"
  client_id: "iiot-example-01"
  qos: 1
  reconnect_delay: 10
influxdb:
  url: "http://influxdb:8086"
  database: "iiot"
sensors:
  - name: "Test Sensor"
    topic: "iiot/test"
    measurement: "environment"
    fields:
      - key: "value"
        json_path: "value"
        type: float
        unit: ""
    tags:
      location: "test"
CONFEOF
fi

info "Config directory ready."

# ── Step 5: Pull images ─────────────────────────────────────────────────
step "5/6" "Pulling Docker images..."

echo "Pulling infrastructure images (influxdb, mosquitto, grafana)..."
docker pull influxdb:1.8 &
docker pull eclipse-mosquitto:2 &
docker pull grafana/grafana:latest &
wait
info "Infrastructure images ready."

echo "Pulling IIoT images (mqtt-reader, web-ui)..."
docker pull "${REGISTRY}/mqtt-reader:${ARCH_TAG}" 2>/dev/null && info "mqtt-reader pulled" || {
  warn "mqtt-reader:${ARCH_TAG} not found on registry yet."
  warn "It will be available after the first CI/CD build completes."
}
docker pull "${REGISTRY}/web-ui:${ARCH_TAG}" 2>/dev/null && info "web-ui pulled" || {
  warn "web-ui:${ARCH_TAG} not found on registry yet."
}

# ── Step 6: Deploy ──────────────────────────────────────────────────────
step "6/6" "Deploying the stack..."

# Update image tags in stack files for this architecture
if [ -f stack.yml ]; then
  sed -i "s|:latest|:${ARCH_TAG}|g" stack.yml
fi
if [ -f docker-compose.yml ]; then
  sed -i "s|:latest|:${ARCH_TAG}|g" docker-compose.yml
fi

if [ "$COMPOSE_MODE" = true ]; then
  info "Deploying with Docker Compose..."
  docker compose up -d --remove-orphans 2>/dev/null || docker-compose up -d --remove-orphans 2>/dev/null || {
    fail "Docker Compose failed. Check: docker compose version"
  }
else
  info "Deploying with Docker Swarm..."
  docker stack deploy -c stack.yml --with-registry-auth "$STACK_NAME" 2>/dev/null || {
    warn "Stack deploy failed — trying Compose instead..."
    docker compose up -d --remove-orphans 2>/dev/null || docker-compose up -d --remove-orphans 2>/dev/null
  }
fi

# ── Done ─────────────────────────────────────────────────────────────────
sleep 3  # Wait for containers to start
HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              Setup Complete!                             ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  📡 Web UI:    http://${HOST_IP}:8080"
echo "  📈 Grafana:   http://${HOST_IP}:3000  (admin / admin)"
echo "  💾 InfluxDB:  http://${HOST_IP}:8086  (database: iiot)"
echo "  📨 MQTT:      ${HOST_IP}:1883"
echo ""
echo "  Next: Open the Web UI to add sensors and MQTT endpoints."
echo "  Everything is managed from the browser — no SSH needed."
echo ""

if [ "$NEED_RELOGIN" = true ]; then
  echo -e "${YELLOW}  NOTE: Docker was installed. Log out and back in for group permissions.${NC}"
  echo -e "${YELLOW}        Then run: cd $(pwd) && ./scripts/deploy.sh${NC}"
fi
