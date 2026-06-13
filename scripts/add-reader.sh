#!/usr/bin/env bash
# Add a new MQTT reader configuration and redeploy.
# Usage: ./add-reader.sh <config-file.yaml>
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <config-file.yaml>"
  echo ""
  echo "Examples:"
  echo "  $0 ./examples/temperature-sensor.yaml"
  echo "  $0 my-mqtt-reader.yaml"
  echo ""
  echo "Create a config file first. See ./config/mqtt-reader-example.yaml for reference."
  exit 1
fi

CONFIG_FILE="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: File not found: $CONFIG_FILE"
  exit 1
fi

# Extract reader name from YAML
READER_NAME=$(grep '^  name:' "$CONFIG_FILE" | head -1 | awk '{print $2}' | tr -d '"' || basename "$CONFIG_FILE" .yaml)
if [ -z "$READER_NAME" ]; then
  READER_NAME=$(basename "$CONFIG_FILE" .yaml)
fi

echo "=== Adding MQTT Reader: $READER_NAME ==="

# Copy config to project config directory
cp "$CONFIG_FILE" "$PROJECT_DIR/config/${READER_NAME}.yaml"
echo "[✓] Config copied to config/${READER_NAME}.yaml"

# Create Docker config (Swarm) or just use bind mount (Compose)
SWARM_ACTIVE=$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo "inactive")

if [ "$SWARM_ACTIVE" = "active" ]; then
  CONFIG_NAME="mqtt-reader-${READER_NAME}"
  docker config rm "$CONFIG_NAME" 2>/dev/null || true
  docker config create "$CONFIG_NAME" "$PROJECT_DIR/config/${READER_NAME}.yaml"
  echo "[✓] Docker config '${CONFIG_NAME}' created"
fi

echo ""
echo "Config added. To activate the reader:"
echo "  1. Add the service to stack.yml or docker-compose.yml"
echo "  2. Run: ./scripts/deploy.sh"
echo ""
echo "Or for quick testing with Compose, add a section like:"
echo ""
echo "  mqtt-reader-${READER_NAME}:"
echo "    image: ghcr.io/sandun-s/industrial-iot-observability-stack/mqtt-reader:latest"
echo "    volumes:"
echo "      - ./config/${READER_NAME}.yaml:/config/reader.yaml:ro"
echo "    environment:"
echo "      CONFIG_PATH: /config/reader.yaml"
