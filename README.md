# Industrial IoT Observability Stack — Deploy

**One-command setup** for the Industrial IoT Observability Stack.

This repository contains everything you need to deploy the IIoT stack on any Linux server or Raspberry Pi running Docker. No source code — just configuration and scripts.

[![GitHub release](https://img.shields.io/github/v/release/Sandun-S/industrial-iot-observability-stack)](https://github.com/Sandun-S/industrial-iot-observability-stack/releases)

## Quick Start

```bash
git clone https://github.com/Sandun-S/industrial-iot-observability-stack-deploy.git
cd industrial-iot-observability-stack-deploy
./scripts/setup.sh
```

That's it. After 2-3 minutes you'll have:
- **Web UI** at `http://<your-ip>:8080`
- **Grafana** at `http://<your-ip>:3000` (admin / admin)
- **InfluxDB** at `http://<your-ip>:8086`
- **MQTT Broker** at `<your-ip>:1883`

## What Gets Deployed

| Service | Port | Purpose |
|---------|------|---------|
| Mosquitto | 1883, 9001 | MQTT broker + WebSocket |
| InfluxDB | 8086 | Time-series database |
| Grafana | 3000 | Dashboards and visualization |
| Web UI | 8080 | Management interface |
| MQTT Reader | — | Subscribes MQTT topics → InfluxDB |

## Requirements

- **Docker** 20.10+ (with Swarm mode for multi-node, or Docker Compose for single host)
- **Linux** (amd64 or arm64 — Raspberry Pi 3/4/5 supported)
- 512MB+ RAM, 2GB+ disk

## Raspberry Pi Setup

```bash
# 1. Install Raspberry Pi OS (64-bit recommended)
# 2. Install Docker
curl -fsSL https://get.docker.com | bash
sudo usermod -aG docker $USER
# Log out and back in

# 3. Clone and run
git clone https://github.com/Sandun-S/industrial-iot-observability-stack-deploy.git
cd industrial-iot-observability-stack-deploy
./scripts/setup.sh
```

## Adding MQTT Readers

Create a YAML config file for each MQTT broker/endpoint:

```bash
# Copy the example
cp config/mqtt-reader-example.yaml config/my-reader.yaml
# Edit it with your broker details and sensors

# Add it to the stack
./scripts/add-reader.sh config/my-reader.yaml
```

See `config/mqtt-reader-example.yaml` for the config format reference.

## Testing

Publish test data to verify the pipeline:

```bash
# Publish a test reading
mosquitto_pub -h localhost -t 'iiot/test' -m '{"value": 23.5, "unit": "C"}'

# Or use the simulator
python3 examples/mqtt-simulator.py --host localhost

# Check InfluxDB
curl "http://localhost:8086/query?db=iiot" --data-urlencode "q=SELECT * FROM environment ORDER BY time DESC LIMIT 5"

# Open Grafana: http://localhost:3000
```

## Auto-Created Dashboards

When you open the Web UI and click "Auto-Create Dashboards," the backend:
1. Discovers all measurements in InfluxDB
2. Creates a Grafana dashboard per measurement
3. Each dashboard includes time-series graphs, stat panels, and device/reading filters

You can also manually create dashboards via the Grafana UI — the InfluxDB datasource is pre-configured.

## Directory Structure

```
├── stack.yml              # Docker Swarm stack (production)
├── docker-compose.yml     # Docker Compose (single host / dev)
├── config/
│   └── mqtt-reader-example.yaml  # Example reader config
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/influxdb.yaml      # Auto InfluxDB datasource
│   │   └── dashboards/
│   │       ├── dashboard-provider.yaml    # Dashboard loader
│   │       └── iiot-overview.json         # Pre-built dashboard
│   └── grafana.ini        # Grafana config (anonymous access)
├── scripts/
│   ├── setup.sh           # One-command full setup
│   ├── deploy.sh          # Redeploy after config changes
│   └── add-reader.sh      # Add new MQTT reader
├── examples/
│   ├── mqtt-simulator.py  # Test data publisher
│   └── temperature-sensor.yaml
├── README.md
├── ARCHITECTURE.md
└── TROUBLESHOOTING.md
```

## Updating

```bash
git pull
./scripts/deploy.sh
```

## License

MIT — see [LICENSE](LICENSE) file.

---

**Source code:** [github.com/Sandun-S/industrial-iot-observability-stack](https://github.com/Sandun-S/industrial-iot-observability-stack)
